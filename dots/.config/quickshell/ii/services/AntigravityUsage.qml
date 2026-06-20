pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

/**
 * Antigravity (agy) usage service — quota only, no tokens, no cost.
 *
 * Token counts and cost MUST NOT be displayed for Antigravity; the API does
 * not expose them and fabricating values would be a correctness violation.
 *
 * Data source:
 *   Quota: POST cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota
 *   Tier:  POST .../v1internal:loadCodeAssist
 *   Token: read at runtime from OS keyring via `secret-tool lookup service
 *          gemini username antigravity`. The token is NEVER stored in any QML
 *          property, file, or log — it lives only in the spawned bash subprocess.
 *
 * User-Agent: antigravity/cli/1.0.9 linux/x86_64 (version confirmed 2026-06-20;
 *   Gemini-CLI UA returns 403 SUBSCRIPTION_REQUIRED — this UA is load-bearing).
 *
 * Curated model subset (ADR-5): display only high-value, quota-constrained models.
 * Matched by modelId prefix so minor version drift is tolerated automatically.
 * Models absent from live buckets are silently omitted (no error).
 *
 * Polling: visibility-gated — only when tabVisible && antigravity.enable.
 */
Singleton {
    id: root

    // ── Visibility gate ─────────────────────────────────────────────────────
    property bool tabVisible: false

    // ── Data properties ──────────────────────────────────────────────────────
    property bool available: false
    property string error: ""
    property string tier: ""

    // Curated model buckets: model display-name -> { usedPercent, resetTime }
    // Populated by _refineBuckets; absent curated models are simply not present.
    property var buckets: ({})

    // ── Loading flag ─────────────────────────────────────────────────────────
    property bool usageLoading: Config.options.sidebar.aiUsage.providers.antigravity.enable

    // ── Curated model list — edit this array to change which models appear ───
    // Matched by prefix against bucket.modelId (tolerates version drift).
    // Order here is the display order in the widget.
    readonly property var _curatedModels: [
        { prefix: "gemini-2.5-pro",            label: "Gemini 2.5 Pro" },
        { prefix: "claude-opus-4-6",            label: "Claude Opus 4.6" },
        { prefix: "claude-sonnet-4-6",          label: "Claude Sonnet 4.6" },
        { prefix: "gemini-2.0-flash",           label: "Gemini 2.0 Flash" }
    ]

    // ── Internal helpers ─────────────────────────────────────────────────────
    function timeUntil(epochMs) {
        DateTime.time;
        if (!epochMs) return "—";
        let diff = Math.floor((epochMs - Date.now()) / 1000);
        if (diff <= 0) return Translation.tr("now");
        const d = Math.floor(diff / 86400);
        diff %= 86400;
        const h = Math.floor(diff / 3600);
        diff %= 3600;
        const m = Math.floor(diff / 60);
        let out = "";
        if (d > 0) out += `${d}d `;
        if (h > 0) out += `${h}h `;
        out += `${m}m`;
        return out.trim();
    }

    // ── Fetch pipeline ───────────────────────────────────────────────────────
    function _fetchQuota() {
        if (!Config.options.sidebar.aiUsage.providers.antigravity.enable) return;
        if (quotaFetcher.running) return;
        root.usageLoading = true;
        quotaFetcher.running = true;
    }

    function _refineBuckets(data) {
        if (data.error) {
            root.available = false;
            root.error = String(data.error);
            root.usageLoading = false;
            return;
        }

        root.tier = data.tier ?? "";

        const rawBuckets = data.buckets ?? [];
        const result = {};

        for (const curatedEntry of root._curatedModels) {
            // Find first bucket whose modelId starts with the curated prefix
            const match = rawBuckets.find(b =>
                typeof b.modelId === "string" &&
                b.modelId.startsWith(curatedEntry.prefix)
            );
            if (!match) continue;

            const remaining = typeof match.remainingFraction === "number"
                ? match.remainingFraction
                : 1.0;

            result[curatedEntry.label] = {
                usedPercent: Math.max(0, Math.min(100, (1.0 - remaining) * 100)),
                resetTime:   match.resetTime ?? null
            };
        }

        root.buckets    = result;
        root.available  = true;
        root.error      = "";
        root.usageLoading = false;
    }

    Process {
        id: quotaFetcher
        // SECURITY: The bearer token is read from the OS keyring inside this
        // subprocess, piped directly into curl, and is NEVER assigned to a QML
        // property, echoed, or written to any file. The jq output deliberately
        // excludes the token. No token literal appears in committed code.
        //
        // User-Agent is load-bearing: antigravity/cli/1.0.9 linux/x86_64.
        // Gemini-CLI UA returns 403 SUBSCRIPTION_REQUIRED for this account type.
        // Version confirmed against `agy --version` output on 2026-06-20.
        command: [
            "bash", "-c",
            // Step 1: read token from keyring; fail gracefully if unavailable
            "if ! command -v secret-tool >/dev/null 2>&1; then " +
            "  echo '{\"error\":\"install libsecret (secret-tool missing)\"}'; exit 0; " +
            "fi; " +
            "tok_json=$(secret-tool lookup service gemini username antigravity 2>/dev/null); " +
            "if [ $? -ne 0 ] || [ -z \"$tok_json\" ]; then " +
            "  echo '{\"error\":\"not signed in (run: agy auth login)\"}'; exit 0; " +
            "fi; " +
            "tok=$(echo \"$tok_json\" | jq -r '.token.access_token // empty' 2>/dev/null); " +
            "if [ -z \"$tok\" ]; then " +
            "  echo '{\"error\":\"not signed in (no access_token in keyring)\"}'; exit 0; " +
            "fi; " +
            // Step 2: fetch quota and tier in parallel (same token, two calls)
            "UA='antigravity/cli/1.0.9 linux/x86_64'; " +
            "q=$(curl -s --max-time 10 " +
            "  -H \"Authorization: Bearer $tok\" " +
            "  -H \"User-Agent: $UA\" " +
            "  -H 'Content-Type: application/json' " +
            "  -d '{}' " +
            "  'https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota' 2>/dev/null); " +
            "c=$(curl -s --max-time 10 " +
            "  -H \"Authorization: Bearer $tok\" " +
            "  -H \"User-Agent: $UA\" " +
            "  -H 'Content-Type: application/json' " +
            "  -d '{\"metadata\":{\"ideType\":\"ANTIGRAVITY\",\"platform\":\"PLATFORM_UNSPECIFIED\",\"pluginType\":\"GEMINI\"}}' " +
            "  'https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist' 2>/dev/null); " +
            // Step 3: merge into compact JSON; token never appears in output
            "jq -cn --argjson q \"$q\" --argjson c \"$c\" " +
            "'{tier: ($c.tier // $c.currentTier.id // null), buckets: ($q.buckets // [])}' " +
            "2>/dev/null || echo '{\"error\":\"unavailable (parse failed)\"}'"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                root.usageLoading = false;
                const raw = text.trim();
                if (raw.length === 0) {
                    root.available = false;
                    root.error = "no response from Antigravity API";
                    return;
                }
                try {
                    const d = JSON.parse(raw);
                    root._refineBuckets(d);
                } catch (e) {
                    root.available = false;
                    root.error = e.message;
                    console.error(`[AntigravityUsage] ${e.message}: ${raw.substring(0, 200)}`);
                }
            }
        }
        onExited: (code, _signal) => {
            if (code !== 0) {
                root.usageLoading = false;
                root.available    = false;
                root.error        = `fetch exited with code ${code}`;
            }
        }
    }

    // ── Public API ───────────────────────────────────────────────────────────
    function refresh() {
        root._fetchQuota();
    }

    // ── Visibility-gated Timer ───────────────────────────────────────────────
    property bool _anyEnabled: Config.options.sidebar.aiUsage.providers.antigravity.enable

    Timer {
        id: pollTimer
        interval: Config.options.sidebar.aiUsage.fetchInterval * 60000
        repeat: true
        running: root._anyEnabled && root.tabVisible
        onTriggered: root.refresh()
    }

    onTabVisibleChanged: {
        if (root.tabVisible && root._anyEnabled) {
            root.refresh();
        }
    }
}
