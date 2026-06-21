pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

// Fetches https://models.dev/api.json once on startup, caches to
// $HOME/.cache/quickshell/modelsdev-pricing.json, and re-fetches if the
// cache file is older than 7 days.
//
// Exposes:
//   ready          - true once JSON is parsed
//   data           - raw parsed object or null
//   price(providerId, modelId) - returns cost object {input,output,cache_read,cache_write} or null
//   cost(providerId, modelId, toks) - returns USD for given token counts or null
//
// cost values from models.dev are USD per 1,000,000 tokens.
Singleton {
    id: root

    // ── Public properties ────────────────────────────────────────────────────
    property bool ready: false
    property var  data:  null

    // ── Pricing lookup ───────────────────────────────────────────────────────
    // Returns the cost object for (providerId, modelId), or null if not found.
    // Lookup order:
    //   1. data.providers[providerId].models[modelId].cost, or root provider map
    //   2. Strip "free/gratis" suffixes and retry paid/base variants
    //   3. Strip any "provider/" prefix from modelId and retry
    //   4. Search ALL providers for modelId key
    function price(providerId, modelId) {
        if (!root.data) return null;
        const providers = root.data.providers ?? root.data;
        if (!providers) return null;

        // Helper: extract cost from a model entry
        function costFrom(entry) {
            if (!entry) return null;
            return entry.cost ?? null;
        }

        function isZeroCost(c) {
            if (!c) return false;
            return (c.input ?? 0) === 0
                && (c.output ?? 0) === 0
                && (c.cache_read ?? 0) === 0
                && (c.cache_write ?? 0) === 0;
        }

        function hasFreeMarker(id) {
            return /(^|[-_./ ])(free|gratis|gratuito)([-_./ ]|$)/i.test(String(id));
        }

        function baseModelId(id) {
            return String(id)
                .replace(/(^|[-_./ ])(free|gratis|gratuito)([-_./ ]|$)/ig, "$1")
                .replace(/[-_./ ]+$/g, "");
        }

        function providerMatches(providerKey) {
            if (!providerId) return false;
            return providerKey === providerId
                || providerKey === `${providerId}-go`
                || providerId === `${providerKey}-go`;
        }

        function exactCostInProvider(pid, id, requireNonZero) {
            const prov = providers[pid];
            if (!prov || !prov.models) return null;
            const c = costFrom(prov.models[id]);
            if (!c) return null;
            if (requireNonZero && isZeroCost(c)) return null;
            return c;
        }

        function exactCostAllProviders(id, requireNonZero) {
            let match = null;
            let ambiguous = false;
            for (const pid of Object.keys(providers)) {
                if (!providerMatches(pid)) continue;
                const c = exactCostInProvider(pid, id, requireNonZero);
                if (c) return c;
            }
            for (const pid of Object.keys(providers)) {
                if (providerMatches(pid)) continue;
                const c = exactCostInProvider(pid, id, requireNonZero);
                if (!c) continue;
                if (!match) {
                    match = c;
                } else {
                    ambiguous = true;
                }
            }
            return ambiguous ? null : match;
        }

        function baseCostForFreeAlias(id) {
            if (!hasFreeMarker(id)) return null;
            const base = baseModelId(id);
            if (!base || base === id) return null;
            return exactCostAllProviders(base, true);
        }

        // 1. Direct lookup
        const directProvider = providers[providerId];
        if (directProvider && directProvider.models) {
            const c = costFrom(directProvider.models[modelId]);
            if (c) {
                const baseCost = isZeroCost(c) ? baseCostForFreeAlias(modelId) : null;
                return baseCost ?? c;
            }
        }

        // 2. Strip provider prefix and retry same provider
        const slashIdx = modelId.indexOf("/");
        if (slashIdx !== -1) {
            const stripped = modelId.slice(slashIdx + 1);
            if (directProvider && directProvider.models) {
                const c = costFrom(directProvider.models[stripped]);
                if (c) {
                    const baseCost = isZeroCost(c) ? baseCostForFreeAlias(stripped) : null;
                    return baseCost ?? c;
                }
            }
        }

        // 3. Search all providers
        for (const pid of Object.keys(providers)) {
            const prov = providers[pid];
            if (!prov || !prov.models) continue;
            const c = costFrom(prov.models[modelId]);
            if (c) {
                const baseCost = isZeroCost(c) ? baseCostForFreeAlias(modelId) : null;
                return baseCost ?? c;
            }
            if (slashIdx !== -1) {
                const stripped = modelId.slice(slashIdx + 1);
                const c2 = costFrom(prov.models[stripped]);
                if (c2) {
                    const baseCost = isZeroCost(c2) ? baseCostForFreeAlias(stripped) : null;
                    return baseCost ?? c2;
                }
            }
        }

        const baseAliasCost = baseCostForFreeAlias(modelId);
        if (baseAliasCost) return baseAliasCost;

        // 4. Fuzzy / partial substring search (e.g. for free/mimo suffixes)
        function normalize(s) {
            return String(s).toLowerCase().replace(/[^a-z0-9]/g, "");
        }

        function canonicalForms(id) {
            const raw = String(id);
            const slashIdx = raw.lastIndexOf("/");
            const stripped = slashIdx !== -1 ? raw.slice(slashIdx + 1) : raw;
            const forms = [
                raw,
                stripped,
                baseModelId(raw),
                baseModelId(stripped)
            ];
            const out = [];
            for (const form of forms) {
                const norm = normalize(form);
                if (norm.length >= 4 && out.indexOf(norm) === -1) out.push(norm);
            }
            return out;
        }

        const normModelForms = canonicalForms(modelId);
        const longestModelForm = normModelForms.reduce((best, form) => Math.max(best, form.length), 0);
        if (longestModelForm >= 6) {
            function costSignature(c) {
                return [
                    c.input ?? "",
                    c.output ?? "",
                    c.cache_read ?? "",
                    c.cache_write ?? ""
                ].join("|");
            }

            function newSearchState() {
                return {
                    cost: null,
                    length: 0,
                    key: "",
                    ambiguous: false
                };
            }

            function bestPairLength(candidateForms) {
                let best = 0;
                let bestKey = "";
                for (const queryForm of normModelForms) {
                    for (const candidateForm of candidateForms) {
                        let len = 0;
                        if (queryForm === candidateForm) {
                            len = queryForm.length + 1000;
                        } else if (queryForm.includes(candidateForm) || candidateForm.includes(queryForm)) {
                            len = Math.min(queryForm.length, candidateForm.length);
                        }
                        if (len > best) {
                            best = len;
                            bestKey = candidateForm;
                        }
                    }
                }
                return { length: best, key: bestKey };
            }

            function considerCandidate(state, mid, entry) {
                const pair = bestPairLength(canonicalForms(mid));
                if (pair.length < 6) return;

                const rawCost = costFrom(entry);
                const c = rawCost && isZeroCost(rawCost)
                    ? (baseCostForFreeAlias(mid) ?? rawCost)
                    : rawCost;
                if (!c) return;

                if (pair.length > state.length) {
                    state.cost = c;
                    state.length = pair.length;
                    state.key = pair.key;
                    state.ambiguous = false;
                    return;
                }

                if (pair.length === state.length) {
                    const sameModel = pair.key === state.key;
                    const sameCost = state.cost && costSignature(c) === costSignature(state.cost);
                    if (!sameModel || !sameCost) state.ambiguous = true;
                }
            }

            function searchInProvider(state, prov) {
                if (!prov || !prov.models) return;
                for (const mid of Object.keys(prov.models)) {
                    considerCandidate(state, mid, prov.models[mid]);
                }
            }

            const providerState = newSearchState();
            for (const pid of Object.keys(providers)) {
                if (providerMatches(pid)) searchInProvider(providerState, providers[pid]);
            }
            if (providerState.cost && !providerState.ambiguous) return providerState.cost;

            const globalState = newSearchState();
            for (const pid of Object.keys(providers)) {
                if (!providerMatches(pid)) searchInProvider(globalState, providers[pid]);
            }
            if (globalState.cost && !globalState.ambiguous) return globalState.cost;
        }

        return null;
    }

    // Returns USD cost for given token counts, or null if price not found.
    // toks: { input, output, cacheRead, cacheWrite }
    // All values are USD per 1M tokens from models.dev.
    function cost(providerId, modelId, toks) {
        const p = root.price(providerId, modelId);
        if (!p) return null;
        return (
            (toks.input     * (p.input       ?? 0)) +
            (toks.output    * (p.output      ?? 0)) +
            (toks.cacheRead * (p.cache_read  ?? 0)) +
            (toks.cacheWrite * (p.cache_write ?? 0))
        ) / 1e6;
    }

    // ── Fetch process ────────────────────────────────────────────────────────
    // Bash script:
    //   1. mkdir -p cache dir
    //   2. Check if cache file is older than 7 days (find -mtime +7)
    //   3. Conditionally curl the JSON into the cache file
    //   4. cat the cache file
    Process {
        id: pricingFetcher
        command: [
            "bash", "-c",
            "cache=\"$HOME/.cache/quickshell/modelsdev-pricing.json\"; " +
            "mkdir -p \"$(dirname \"$cache\")\"; " +
            "stale=$(find \"$cache\" -mtime +7 2>/dev/null); " +
            "if [ ! -f \"$cache\" ] || [ -n \"$stale\" ]; then " +
            "  curl -s --max-time 15 'https://models.dev/api.json' -o \"$cache\" 2>/dev/null; " +
            "fi; " +
            "cat \"$cache\" 2>/dev/null || echo 'null'"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (!raw || raw === "null") {
                    console.warn("[ModelPricing] No data from models.dev cache");
                    return;
                }
                try {
                    const parsed = JSON.parse(raw);
                    root.data  = parsed;
                    root.ready = true;
                } catch (e) {
                    console.error(`[ModelPricing] JSON parse error: ${e.message}`);
                }
            }
        }
        onExited: (code, _signal) => {
            if (code !== 0) {
                console.warn(`[ModelPricing] fetch process exited with code ${code}`);
            }
        }
    }

    Component.onCompleted: {
        pricingFetcher.running = true;
    }
}
