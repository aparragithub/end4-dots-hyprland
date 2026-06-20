pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

/**
 * AI provider usage service — quota (remaining) and spend.
 *
 * Claude is the only provider implemented in this cut. The service is keyed
 * by provider so Codex / opencode slot in without reshaping existing logic.
 *
 * Quota source:  OAuth endpoint https://api.anthropic.com/api/oauth/usage
 *                Token read from ~/.claude/.credentials.json (kept fresh by
 *                Claude Code). Logic adapted from upstream PR end-4/dots-hyprland#3468.
 *
 * Spend source:  npx ccusage@latest --json (reads local session logs; handles
 *                pricing). Requires Node runtime.
 *
 * Polling:       Visibility-gated — only while tabVisible is true and at least
 *                one provider is enabled. fetchInterval minutes between cycles;
 *                immediate fetch on tab-open; click-to-refresh via refresh().
 */
Singleton {
    id: root

    // ── Visibility gate ─────────────────────────────────────────────────────
    // Set to true by AiUsageWidget when the tab is active; false when hidden.
    property bool tabVisible: false

    // ── Claude: quota (OAuth) ────────────────────────────────────────────────
    property bool claudeAvailable: false
    property string claudeError: ""
    property string subscriptionType: ""

    // Utilization 0-100; -1 means "not reported by the API"
    property real fiveHour: 0
    property real sevenDay: 0

    // Reset timestamps (epoch ms; 0 if unknown)
    property double fiveHourReset: 0
    property double sevenDayReset: 0

    // ── Claude: spend (ccusage) ──────────────────────────────────────────────
    property bool spentAvailable: false
    property string spentError: ""

    property real spentTodayCost: 0
    property real spentWeekCost: 0
    property real spentMonthCost: 0
    property int  spentTodayTokens: 0

    // ── Loading flags ────────────────────────────────────────────────────────
    property bool quotaLoading: false
    property bool spentLoading: false

    // ── Internal helpers ─────────────────────────────────────────────────────
    function _parseIso(s) {
        if (!s) return 0;
        const t = Date.parse(s);
        return isNaN(t) ? 0 : t;
    }

    // Human "2h 5m" until the given epoch-ms. References DateTime.time so it
    // recomputes on the clock tick.
    function timeUntil(epochMs) {
        DateTime.time; // reactivity dependency
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

    // ── Quota fetch ──────────────────────────────────────────────────────────
    function _fetchQuota() {
        if (!Config.options.sidebar.aiUsage.providers.claude.enable) return;
        if (quotaFetcher.running) return;
        root.quotaLoading = true;
        quotaFetcher.running = true;
    }

    function _refineQuota(data) {
        root.subscriptionType   = data.subscriptionType ?? "";
        root.fiveHour           = data.five_hour?.utilization ?? 0;
        root.sevenDay           = data.seven_day?.utilization ?? 0;
        root.fiveHourReset      = root._parseIso(data.five_hour?.resets_at);
        root.sevenDayReset      = root._parseIso(data.seven_day?.resets_at);
        root.claudeAvailable    = true;
        root.claudeError        = "";
        root.quotaLoading       = false;
    }

    Process {
        id: quotaFetcher
        // Read token from credentials file, then call the usage endpoint.
        // Adapted verbatim from end-4/dots-hyprland PR #3468 ClaudeUsage.qml.
        command: [
            "bash", "-c",
            "creds=\"$HOME/.claude/.credentials.json\"; " +
            "tok=$(jq -r '.claudeAiOauth.accessToken' \"$creds\" 2>/dev/null); " +
            "sub=$(jq -r '.claudeAiOauth.subscriptionType' \"$creds\" 2>/dev/null); " +
            "if [ -z \"$tok\" ] || [ \"$tok\" = null ]; then " +
            "  echo '{\"error\":\"no Claude token\"}'; exit 0; " +
            "fi; " +
            "curl -s --max-time 10 " +
            "-H \"Authorization: Bearer $tok\" " +
            "-H \"anthropic-beta: oauth-2025-04-20\" " +
            "-H \"anthropic-version: 2023-06-01\" " +
            "https://api.anthropic.com/api/oauth/usage " +
            "| jq -c --arg sub \"$sub\" '. + {subscriptionType:$sub}'"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                root.quotaLoading = false;
                const raw = text.trim();
                if (raw.length === 0) {
                    root.claudeAvailable = false;
                    root.claudeError = "empty response";
                    return;
                }
                try {
                    const d = JSON.parse(raw);
                    if (d.error) {
                        root.claudeAvailable = false;
                        root.claudeError = String(d.error);
                        return;
                    }
                    root._refineQuota(d);
                } catch (e) {
                    root.claudeAvailable = false;
                    root.claudeError = e.message;
                    console.error(`[AiUsage/quota] ${e.message}: ${raw}`);
                }
            }
        }
    }

    // ── Spend fetch ──────────────────────────────────────────────────────────
    function _fetchSpend() {
        if (!Config.options.sidebar.aiUsage.providers.claude.enable) return;
        if (spendFetcher.running) return;
        root.spentLoading = true;
        spendFetcher.running = true;
    }

    function _refineSpend(data) {
        // ccusage --json returns an array of daily/weekly/monthly breakdown rows.
        // Structure: { daily: [{...}], weekly: [{...}], monthly: [{...}] }
        // Each period has rows keyed by model; we want aggregate totals.
        // Alternatively, ccusage may return a flat array with a "period" field.
        // We handle both shapes defensively.
        let todayCost = 0, weekCost = 0, monthCost = 0, todayTokens = 0;

        function sumPeriod(rows) {
            let cost = 0, tokens = 0;
            if (!Array.isArray(rows)) return { cost, tokens };
            for (const row of rows) {
                cost   += (row.totalCost   ?? row.cost   ?? 0);
                tokens += (row.totalTokens ?? row.tokens ?? 0);
            }
            return { cost, tokens };
        }

        if (Array.isArray(data)) {
            // Flat array with period discriminator
            const daily   = data.filter(r => r.period === "daily"   || r.period === "today");
            const weekly  = data.filter(r => r.period === "weekly"  || r.period === "week");
            const monthly = data.filter(r => r.period === "monthly" || r.period === "month");
            todayCost   = sumPeriod(daily).cost;
            weekCost    = sumPeriod(weekly).cost;
            monthCost   = sumPeriod(monthly).cost;
            todayTokens = sumPeriod(daily).tokens;
        } else {
            // Structured object shape: { daily: [...], weekly: [...], monthly: [...] }
            const d = sumPeriod(data.daily   ?? data.today);
            const w = sumPeriod(data.weekly  ?? data.week);
            const m = sumPeriod(data.monthly ?? data.month);
            todayCost   = d.cost;
            weekCost    = w.cost;
            monthCost   = m.cost;
            todayTokens = d.tokens;
        }

        root.spentTodayCost   = todayCost;
        root.spentWeekCost    = weekCost;
        root.spentMonthCost   = monthCost;
        root.spentTodayTokens = todayTokens;
        root.spentAvailable   = true;
        root.spentError       = "";
        root.spentLoading     = false;
    }

    Process {
        id: spendFetcher
        // npx ccusage@latest --json — requires Node. On Arch, nodejs must be in
        // the PKGBUILD depends (declared in illogical-impulse-basic). If the AUR
        // ccusage package is installed, the `ccusage` binary is available directly;
        // npx falls back gracefully when it is.
        command: ["bash", "-c", "npx ccusage@latest --json 2>/dev/null || exit 1"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.spentLoading = false;
                const raw = text.trim();
                if (raw.length === 0) {
                    root.spentAvailable = false;
                    root.spentError = "ccusage not installed or returned no output";
                    return;
                }
                try {
                    const d = JSON.parse(raw);
                    root._refineSpend(d);
                } catch (e) {
                    root.spentAvailable = false;
                    root.spentError = e.message;
                    console.error(`[AiUsage/spend] ${e.message}: ${raw.substring(0, 200)}`);
                }
            }
        }
        onExited: (code, signal) => {
            if (code !== 0) {
                root.spentLoading   = false;
                root.spentAvailable = false;
                root.spentError     = `ccusage exited with code ${code}`;
            }
        }
    }

    // ── Public API ───────────────────────────────────────────────────────────
    function refresh() {
        root._fetchQuota();
        root._fetchSpend();
    }

    // ── Visibility-gated Timer ───────────────────────────────────────────────
    property bool _anyEnabled: Config.options.sidebar.aiUsage.providers.claude.enable

    Timer {
        id: pollTimer
        interval: Config.options.sidebar.aiUsage.fetchInterval * 60000
        repeat: true
        running: root._anyEnabled && root.tabVisible
        onTriggered: root.refresh()
    }

    // Fetch immediately when the tab becomes visible
    onTabVisibleChanged: {
        if (root.tabVisible && root._anyEnabled) {
            root.refresh();
        }
    }
}
