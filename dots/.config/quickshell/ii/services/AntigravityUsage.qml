pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

/**
 * Antigravity (agy) usage service — grouped quota only, no tokens, no cost.
 *
 * Token counts and cost MUST NOT be displayed for Antigravity; the API does
 * not expose them and fabricating values would be a correctness violation.
 *
 * Data source:
 *   POST https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary
 *   Token: read at runtime from OS keyring via `secret-tool lookup service
 *          gemini username antigravity`. The token is NEVER stored in any QML
 *          property, file, or log — it lives only in the spawned bash subprocess.
 *
 * Response model: groups[] → each group has displayName + buckets[].
 * Each bucket has: window ("weekly" | "5h"), displayName, remainingFraction,
 * resetTime (ISO-8601 UTC string).
 *
 * usedPercent = (1 - remainingFraction) * 100 — consistent with Claude/Codex
 * gauges (red near limit = high used %).
 *
 * User-Agent: antigravity/cli/1.0.9 linux/x86_64 (version confirmed 2026-06-20;
 *   Gemini-CLI UA returns 403 SUBSCRIPTION_REQUIRED — this UA is load-bearing).
 *
 * Polling: visibility-gated — only when tabVisible && antigravity.enable.
 *
 * ADR-7 (supersedes ADR-5): server provides grouping via retrieveUserQuotaSummary.
 * No client-side curated model list needed; groups and labels are server-driven.
 */
Singleton {
    id: root

    // ── Visibility gate ─────────────────────────────────────────────────────
    property bool tabVisible: false

    // ── Data properties ──────────────────────────────────────────────────────
    property bool available: false
    property string error: ""

    // groups: array of { name: string, buckets: [{ window, displayName, usedPercent, resetTime }] }
    // Populated by _parseGroups on successful fetch.
    property var groups: []

    // ── Loading flag ─────────────────────────────────────────────────────────
    property bool usageLoading: Config.options.sidebar.aiUsage.providers.antigravity.enable

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

    function _parseGroups(data) {
        if (data.error) {
            root.available    = false;
            root.error        = String(data.error);
            root.usageLoading = false;
            return;
        }

        const rawGroups = data.groups ?? [];
        const result = [];

        for (const g of rawGroups) {
            const name = g.displayName ?? "";
            const buckets = [];
            for (const b of (g.buckets ?? [])) {
                const remaining = typeof b.remainingFraction === "number"
                    ? b.remainingFraction
                    : 1.0;
                buckets.push({
                    window:      b.window      ?? "",
                    displayName: b.displayName ?? b.window ?? "",
                    usedPercent: Math.max(0, Math.min(100, (1.0 - remaining) * 100)),
                    resetTime:   b.resetTime   ?? null
                });
            }
            result.push({ name, buckets });
        }

        root.groups       = result;
        root.available    = result.length > 0;
        root.error        = result.length > 0 ? "" : "unavailable (empty response)";
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
            // Step 1b: check token expiry
            "expiry=$(echo \"$tok_json\" | jq -r '.token.expiry // empty' 2>/dev/null); " +
            "if [ -n \"$expiry\" ]; then " +
            "  expiry_epoch=$(date -d \"$expiry\" +%s 2>/dev/null || echo 0); " +
            "  now_epoch=$(date +%s); " +
            "  if [ \"$expiry_epoch\" -le \"$now_epoch\" ]; then " +
            "    echo '{\"error\":\"token expired (reopen Antigravity IDE to refresh)\"}'; exit 0; " +
            "  fi; " +
            "fi; " +
            // Step 2: call retrieveUserQuotaSummary — server provides grouped weekly+5h data
            "UA='antigravity/cli/1.0.9 linux/x86_64'; " +
            "resp=$(curl -s --max-time 10 " +
            "  -X POST " +
            "  -H \"Authorization: Bearer $tok\" " +
            "  -H \"User-Agent: $UA\" " +
            "  -H 'Content-Type: application/json' " +
            "  -d '{}' " +
            "  'https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary' 2>/dev/null); " +
            // Step 3: detect API errors (401, 403, etc.) before extracting groups
            "if echo \"$resp\" | jq -e '.error' >/dev/null 2>&1; then " +
            "  err_msg=$(echo \"$resp\" | jq -r '.error.message // .error.code // \"API error\"' 2>/dev/null); " +
            "  echo \"{\\\"error\\\":\\\"${err_msg}\\\"}\"; " +
            "else " +
            "  echo \"$resp\" | jq -c '{groups: (.groups // [])}'; " +
            "fi " +
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
                    root._parseGroups(d);
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
