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
    //   1. data.providers[providerId].models[modelId].cost
    //   2. Strip any "provider/" prefix from modelId and retry same provider
    //   3. Search ALL providers for modelId key
    function price(providerId, modelId) {
        if (!root.data) return null;
        const providers = root.data.providers;
        if (!providers) return null;

        // Helper: extract cost from a model entry
        function costFrom(entry) {
            if (!entry) return null;
            return entry.cost ?? null;
        }

        // 1. Direct lookup
        const directProvider = providers[providerId];
        if (directProvider && directProvider.models) {
            const c = costFrom(directProvider.models[modelId]);
            if (c) return c;
        }

        // 2. Strip provider prefix and retry same provider
        const slashIdx = modelId.indexOf("/");
        if (slashIdx !== -1) {
            const stripped = modelId.slice(slashIdx + 1);
            if (directProvider && directProvider.models) {
                const c = costFrom(directProvider.models[stripped]);
                if (c) return c;
            }
        }

        // 3. Search all providers
        for (const pid of Object.keys(providers)) {
            const prov = providers[pid];
            if (!prov || !prov.models) continue;
            const c = costFrom(prov.models[modelId]);
            if (c) return c;
            if (slashIdx !== -1) {
                const stripped = modelId.slice(slashIdx + 1);
                const c2 = costFrom(prov.models[stripped]);
                if (c2) return c2;
            }
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
