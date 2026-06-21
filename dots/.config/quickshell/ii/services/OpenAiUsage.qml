pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

/**
 * Codex (OpenAI) usage service — quota and estimated API-rate cost.
 *
 * Data source: local files under ~/.codex/sessions/<date>/rollout-*.jsonl
 * No network requests are made. All values derive from the newest rollout
 * file's last event_msg with payload.type == "token_count".
 *
 * Quota:  payload.rate_limits.{primary,secondary} (5h and 7d windows)
 * Tokens: payload.info.total_token_usage (session-cumulative per file)
 * Cost:   tokens × pricing table below (estimated API-rate cost, not a bill)
 *
 * Polling: visibility-gated — only when tabVisible && openai.enable.
 *
 * Note: token aggregation across sessions sums each rollout file's last
 * token_count event. This is an upper-bound estimate because total_token_usage
 * is session-cumulative; it is clearly labeled as "estimated API-rate cost".
 *
 * jq path confirmed 2026-06-20: payload.info.total_token_usage (NOT
 * payload.total_token_usage — that field is always null in live rollouts).
 */
Singleton {
    id: root

    // ── Visibility gate ─────────────────────────────────────────────────────
    // Set by AiUsageWidget when the AI Usage tab is active.
    property bool tabVisible: false

    // ── Data properties ──────────────────────────────────────────────────────
    property bool available: false
    property string error: ""
    property string subscriptionType: ""

    // Quota utilization 0–100; -1 = not reported
    property real fiveHour: -1
    property real sevenDay: -1

    // Reset timestamps (epoch seconds from API; multiplied to ms in _refine)
    property double fiveHourReset: 0
    property double sevenDayReset: 0

    // Token counts (session-cumulative per-file sums; see aggregation note above)
    property int spentTodayTokens: 0
    property int spentWeekTokens: 0

    // Estimated API-rate cost (USD). Clearly labeled in widget — not a bill.
    property real spentTodayCost: 0
    property real spentWeekCost: 0

    // Token split totals for today (input net, output, cache read)
    property int spentTodayInputTokens: 0
    property int spentTodayOutputTokens: 0
    property int spentTodayCacheTokens: 0

    // ── Loading flag ─────────────────────────────────────────────────────────
    property bool usageLoading: Config.options.sidebar.aiUsage.providers.openai.enable

    // Hardcoded fallback rate (USD per token) used when ModelPricing has no entry.
    // 1.25 per 1M tokens — roughly gpt-5-codex input rate.
    readonly property real _fallbackRatePerToken: 1.25 / 1e6

    // ── Internal helpers ─────────────────────────────────────────────────────
    function _parseIso(s) {
        if (!s) return 0;
        const t = Date.parse(s);
        return isNaN(t) ? 0 : t;
    }

    // Human "2h 5m" until the given epoch-ms. References DateTime.time so it
    // recomputes on the clock tick.
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

    // YYYY-MM-DD string for a Date object (used to bucket file paths by date).
    function _ymd(d) {
        const y = d.getFullYear();
        const mo = String(d.getMonth() + 1).padStart(2, "0");
        const dy = String(d.getDate()).padStart(2, "0");
        return `${y}-${mo}-${dy}`;
    }

    // ── Quota + current-session fetch ─────────────────────────────────────────
    function _fetchUsage() {
        if (!Config.options.sidebar.aiUsage.providers.openai.enable) return;
        if (usageFetcher.running) return;
        root.usageLoading = true;
        usageFetcher.running = true;
    }

    // Parse the newest rollout file's last token_count event for quota + session tokens.
    function _refineUsage(data) {
        if (data.error) {
            root.available = false;
            root.error = String(data.error);
            root.usageLoading = false;
            return;
        }

        const rl = data.rate_limits;
        if (!rl) {
            root.available = false;
            root.error = "rate_limits missing in token_count event";
            root.usageLoading = false;
            return;
        }

        root.subscriptionType = rl.plan_type ?? "";
        root.fiveHour         = rl.primary?.used_percent  ?? -1;
        root.sevenDay         = rl.secondary?.used_percent ?? -1;

        // resets_at is epoch seconds (integer) in the live data.
        root.fiveHourReset  = (rl.primary?.resets_at  ?? 0) * 1000;
        root.sevenDayReset  = (rl.secondary?.resets_at ?? 0) * 1000;

        // Session tokens from payload.info.total_token_usage
        const tu = data.session_tokens;
        if (tu) {
            const modelId    = data.model_id ?? "gpt-5-codex";
            const inputNet   = (tu.input_tokens ?? 0) - (tu.cached_input_tokens ?? 0);
            const outputTotal = (tu.output_tokens ?? 0) + (tu.reasoning_output_tokens ?? 0);
            const cacheRead  = tu.cached_input_tokens ?? 0;

            root.spentTodayTokens        = tu.total_tokens ?? 0;
            root.spentTodayInputTokens   = inputNet;
            root.spentTodayOutputTokens  = outputTotal;
            root.spentTodayCacheTokens   = cacheRead;

            const est = ModelPricing.cost("openai", modelId, {
                input:      inputNet,
                output:     outputTotal,
                cacheRead:  cacheRead,
                cacheWrite: 0
            });
            root.spentTodayCost = est !== null
                ? est
                : (inputNet + cacheRead + outputTotal) * root._fallbackRatePerToken;
        }

        root.available    = true;
        root.error        = "";
        root.usageLoading = false;
    }

    Process {
        id: usageFetcher
        // Newest rollout file discovery uses `find` (coreutils) — NOT fd.
        // Extracts quota fields and session token usage from the last token_count event.
        //
        // jq path confirmed 2026-06-20: total_token_usage lives under
        // payload.info.total_token_usage (payload.total_token_usage is always null).
        command: [
            "bash", "-c",
            "base=\"$HOME/.codex/sessions\"; " +
            "f=$(find \"$base\" -type f -name 'rollout-*.jsonl' -printf '%T@ %p\\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-); " +
            "if [ -z \"$f\" ]; then echo '{\"error\":\"no codex sessions\"}'; exit 0; fi; " +
            "last=$(grep -F '\"type\":\"token_count\"' \"$f\" | tail -1); " +
            "if [ -z \"$last\" ]; then echo '{\"error\":\"no usage yet\"}'; exit 0; fi; " +
            "echo \"$last\" | jq -c '{" +
            "rate_limits: .payload.rate_limits, " +
            "session_tokens: .payload.info.total_token_usage, " +
            "model_id: (.payload.info.model_id // .payload.model_id // \"gpt-5-codex\")" +
            "}'"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                root.usageLoading = false;
                const raw = text.trim();
                if (raw.length === 0) {
                    root.available = false;
                    root.error = "no output from rollout parser";
                    return;
                }
                try {
                    const d = JSON.parse(raw);
                    root._refineUsage(d);
                } catch (e) {
                    root.available = false;
                    root.error = e.message;
                    console.error(`[OpenAiUsage/usage] ${e.message}: ${raw}`);
                }
            }
        }
        onExited: (code, _signal) => {
            if (code !== 0) {
                root.usageLoading = false;
                root.available    = false;
                root.error        = `rollout parser exited ${code}`;
            }
        }
    }

    // ── Weekly token aggregation fetch ───────────────────────────────────────
    // Sums the last token_count event from each rollout file within the past 7
    // calendar days. This is an upper-bound estimate (session-cumulative sums).
    function _fetchWeekly() {
        if (!Config.options.sidebar.aiUsage.providers.openai.enable) return;
        if (weeklyFetcher.running) return;
        weeklyFetcher.running = true;
    }

    function _refineWeekly(rows) {
        if (!Array.isArray(rows)) return;
        const now       = new Date();
        const todayStr  = root._ymd(now);
        const weekStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6);

        let weekTokens = 0, weekCost = 0;

        for (const row of rows) {
            const d = new Date(`${row.date}T00:00:00`);
            if (isNaN(d.getTime())) continue;
            if (d >= weekStart) {
                const tok = row.tok ?? 0;
                weekTokens += tok;
                const est = ModelPricing.cost("openai", "gpt-5-codex", {
                    input: tok, output: 0, cacheRead: 0, cacheWrite: 0
                });
                weekCost += est !== null ? est : tok * root._fallbackRatePerToken;
            }
        }

        root.spentWeekTokens = weekTokens;
        root.spentWeekCost   = weekCost;
    }

    Process {
        id: weeklyFetcher
        // Enumerate all rollout files, take each file's last token_count event,
        // extract date (from YYYY/MM/DD path segment) and total_tokens.
        // Uses payload.info.total_token_usage (confirmed path).
        command: [
            "bash", "-c",
            "base=\"$HOME/.codex/sessions\"; " +
            "find \"$base\" -type f -name 'rollout-*.jsonl' -printf '%p\\n' 2>/dev/null | " +
            "while read f; do " +
            "  d=$(echo \"$f\" | grep -oE '[0-9]{4}/[0-9]{2}/[0-9]{2}' | head -1 | tr / -); " +
            "  t=$(grep -F '\"type\":\"token_count\"' \"$f\" | tail -1 | " +
            "      jq -r '.payload.info.total_token_usage.total_tokens // 0' 2>/dev/null); " +
            "  [ -n \"$d\" ] && [ -n \"$t\" ] && echo \"$d $t\"; " +
            "done | " +
            "jq -Rs '[split(\"\\n\")[] | select(length>0) | split(\" \") | {date:.[0], tok:(.[1]|tonumber)}]'"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (raw.length === 0) return;
                try {
                    const rows = JSON.parse(raw);
                    root._refineWeekly(rows);
                } catch (e) {
                    console.error(`[OpenAiUsage/weekly] ${e.message}: ${raw.substring(0, 200)}`);
                }
            }
        }
    }

    // ── Public API ───────────────────────────────────────────────────────────
    function refresh() {
        root._fetchUsage();
        root._fetchWeekly();
    }

    // ── Visibility-gated Timer ───────────────────────────────────────────────
    property bool _anyEnabled: Config.options.sidebar.aiUsage.providers.openai.enable

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
