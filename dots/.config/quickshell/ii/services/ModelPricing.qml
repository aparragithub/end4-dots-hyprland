pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

// Fetches https://models.dev/api.json and https://openrouter.ai/api/v1/models
// once on startup, caches both to ~/.cache/quickshell/, re-fetches if cache
// is older than 7 days.
//
// Pricing sources (in priority order):
//   1. models.dev — broad coverage, community-maintained
//   2. OpenRouter — fallback when models.dev cost is $0 or missing
//
// Exposes:
//   ready          - true once JSON is parsed
//   data           - raw parsed models.dev object or null
//   price(providerId, modelId) - returns cost object {input,output,cache_read,cache_write} or null
//   cost(providerId, modelId, toks) - returns USD for given token counts or null
//
// cost values: models.dev returns USD per 1,000,000 tokens.
//              OpenRouter returns USD per 1 token → multiplied by 1e6 to match.
Singleton {
    id: root

    // ── Public properties ────────────────────────────────────────────────────
    property bool ready: false
    property var  data:  null

    // OpenRouter fallback data — indexed by model ID for O(1) lookup
    property var _openrouterModels: ({})

    // ── Shared helpers ─────────────────────────────────────────────────────────
    function _isZeroCost(c) {
        if (!c) return false;
        return (c.input ?? 0) === 0
            && (c.output ?? 0) === 0
            && (c.cache_read ?? 0) === 0
            && (c.cache_write ?? 0) === 0;
    }

    function _hasFreeMarker(id) {
        return /(^|[-_./ ])(free|gratis|gratuito)([-_./ ]|$)/i.test(String(id));
    }

    function _baseModelId(id) {
        return String(id)
            .replace(/(^|[-_./ ])(free|gratis|gratuito)([-_./ ]|$)/ig, "$1")
            .replace(/[-_./ ]+$/g, "");
    }

    function _normalize(s) {
        return String(s).toLowerCase().replace(/[^a-z0-9]/g, "");
    }

    // ── Pricing lookup ───────────────────────────────────────────────────────
    // Returns the cost object for (providerId, modelId), or null if not found.
    // Tries models.dev first, then falls back to OpenRouter.
    function price(providerId, modelId) {
        const mdResult = _priceModelsDev(providerId, modelId);
        return _tryOpenRouterFallback(providerId, modelId, mdResult);
    }

    function _priceModelsDev(providerId, modelId) {
        if (!root.data) return null;
        const providers = root.data.providers ?? root.data;
        if (!providers) return null;

        // Helper: extract cost from a model entry
        function costFrom(entry) {
            if (!entry) return null;
            return entry.cost ?? null;
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
            if (requireNonZero && root._isZeroCost(c)) return null;
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
            if (!root._hasFreeMarker(id)) return null;
            const base = root._baseModelId(id);
            if (!base || base === id) return null;
            return exactCostAllProviders(base, true);
        }

        // 1. Direct lookup
        const directProvider = providers[providerId];
        if (directProvider && directProvider.models) {
            const c = costFrom(directProvider.models[modelId]);
            if (c) {
                const baseCost = root._isZeroCost(c) ? baseCostForFreeAlias(modelId) : null;
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
                    const baseCost = root._isZeroCost(c) ? baseCostForFreeAlias(stripped) : null;
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
                const baseCost = root._isZeroCost(c) ? baseCostForFreeAlias(modelId) : null;
                return baseCost ?? c;
            }
            if (slashIdx !== -1) {
                const stripped = modelId.slice(slashIdx + 1);
                const c2 = costFrom(prov.models[stripped]);
                if (c2) {
                    const baseCost = root._isZeroCost(c2) ? baseCostForFreeAlias(stripped) : null;
                    return baseCost ?? c2;
                }
            }
        }

        const baseAliasCost = baseCostForFreeAlias(modelId);
        if (baseAliasCost) return baseAliasCost;

        // 4. Fuzzy / partial substring search (e.g. for free/mimo suffixes)

        function canonicalForms(id) {
            const raw = String(id);
            const slashIdx = raw.lastIndexOf("/");
            const stripped = slashIdx !== -1 ? raw.slice(slashIdx + 1) : raw;
            const forms = [
                raw,
                stripped,
                root._baseModelId(raw),
                root._baseModelId(stripped)
            ];
            const out = [];
            for (const form of forms) {
                const norm = root._normalize(form);
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
                const c = rawCost && root._isZeroCost(rawCost)
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

        // OpenRouter fallback: try when models.dev returned null or zero-cost
        // without a "free"/"gratis" marker (likely missing pricing data)
        const mdResult = null; // fell through all lookups above
        return _tryOpenRouterFallback(providerId, modelId, mdResult);
    }

    function _tryOpenRouterFallback(providerId, modelId, mdResult) {
        const orCost = root._openRouterCost(modelId, providerId);
        if (!orCost) return mdResult;
        // OpenRouter cost found — prefer it over null or $0 models.dev data
        if (!mdResult) return orCost;
        if (root._isZeroCost(mdResult) && !root._hasFreeMarker(modelId)) return orCost;
        return mdResult;
    }

    // ── OpenRouter fallback lookup ────────────────────────────────────────────
    // OpenRouter pricing is per token; we multiply by 1e6 to match models.dev's
    // per-1M-tokens convention.
    function _openRouterCost(modelId, providerId) {
        if (!root._openrouterModels || Object.keys(root._openrouterModels).length === 0)
            return null;

        // 1. Direct match on modelId as stored in OpenRouter
        const direct = root._openrouterModels[modelId];
        if (direct) return direct;

        // 2. Search by normalized substring — match the model part after provider/
        const normQuery = root._normalize(String(modelId));
        if (normQuery.length < 4) return null;

        // Build candidate search forms, including expanded abbreviations
        // (e.g. k2p7 → k2.7, deepseek-v4 → deepseekv4)
        const candidates = [];
        const rawId = String(modelId);
        const stripped = rawId.replace(/^.*\//, "");
        candidates.push(rawId, stripped);

        // Expand k[N]p[M] pattern → k[N].[M] (OpenCode abbreviates Kimi versions)
        const kpMatch = stripped.match(/^k(\d+)p(\d+)(.*)$/i);
        if (kpMatch) {
            candidates.push("k" + kpMatch[1] + "." + kpMatch[2] + (kpMatch[3] || ""));
            candidates.push("kimi-k" + kpMatch[1] + "." + kpMatch[2] + (kpMatch[3] || ""));
        }

        // Generate forms with common provider prefixes
        const providerNorm = root._normalize(String(providerId ?? ""));
        for (const c of [...candidates]) {
            if (providerNorm.length > 0) {
                candidates.push(providerNorm + "/" + c);
            }
        }

        let best = null;
        let bestLen = 0;

        for (const orId of Object.keys(root._openrouterModels)) {
            const orModel = orId.replace(/^.*\//, ""); // strip provider/ prefix
            const normOr = root._normalize(orModel);
            if (normOr.length < 4) continue;

            for (const cand of candidates) {
                const normCand = root._normalize(String(cand));
                if (normCand.length < 4) continue;

                let len = 0;
                if (normOr === normCand) {
                    len = normOr.length + 100;
                } else if (normOr.includes(normCand) || normCand.includes(normOr)) {
                    len = Math.min(normOr.length, normCand.length);
                }
                if (len > bestLen && len >= 4) {
                    best = root._openrouterModels[orId];
                    bestLen = len;
                }
            }
        }

        return best;
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

    // ── OpenRouter fetch (fallback pricing source) ────────────────────────────
    // OpenRouter pricing is per token; we normalize to per-1M-tokens inside
    // _loadOpenRouter to keep the internal cost format consistent.
    Process {
        id: orPricingFetcher
        command: [
            "bash", "-c",
            "cache=\"$HOME/.cache/quickshell/openrouter-pricing.json\"; " +
            "mkdir -p \"$(dirname \"$cache\")\"; " +
            "stale=$(find \"$cache\" -mtime +1 2>/dev/null); " +
            "if [ ! -f \"$cache\" ] || [ -n \"$stale\" ]; then " +
            "  curl -s --max-time 15 'https://openrouter.ai/api/v1/models' -o \"$cache\" 2>/dev/null; " +
            "fi; " +
            "cat \"$cache\" 2>/dev/null || echo '{\"data\":[]}'"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (!raw || raw === "null") {
                    console.warn("[ModelPricing] No data from OpenRouter cache");
                    return;
                }
                try {
                    const parsed = JSON.parse(raw);
                    root._loadOpenRouter(parsed);
                } catch (e) {
                    console.error(`[ModelPricing] OpenRouter JSON parse error: ${e.message}`);
                }
            }
        }
        onExited: (code, _signal) => {
            if (code !== 0) {
                console.warn(`[ModelPricing] OpenRouter fetch exited with code ${code}`);
            }
        }
    }

    // Index OpenRouter data by model ID for O(1) lookup.
    // Multiply per-token pricing by 1e6 to match models.dev's per-1M-tokens format.
    // Also builds a secondary index keyed by normalized model slug for fuzzy matching.
    function _loadOpenRouter(orData) {
        const models = {};
        const data = orData.data ?? [];
        for (const m of data) {
            const p = m.pricing;
            if (!p) continue;
            const cost = {
                input:      (parseFloat(p.prompt ?? 0)            * 1e6),
                output:     (parseFloat(p.completion ?? 0)        * 1e6),
                cache_read: (parseFloat(p.input_cache_read ?? 0)  * 1e6),
                cache_write: (parseFloat(p.input_cache_write ?? p.input_cache_read ?? 0) * 1e6)
            };
            if (root._isZeroCost(cost)) continue; // skip free/unpriced models
            models[m.id] = cost;
        }
        root._openrouterModels = models;
        console.log(`[ModelPricing] OpenRouter: indexed ${Object.keys(models).length} priced models`);
    }

    Component.onCompleted: {
        pricingFetcher.running   = true;
        orPricingFetcher.running = true;
    }
}
