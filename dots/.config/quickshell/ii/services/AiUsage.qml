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
 * Spend source:  ccusage --json — prefers an installed ccusage binary and
 *                falls back to `npx --yes ccusage` (no @latest, to avoid a
 *                network version check). Reads local session logs; needs Node
 *                for the npx fallback.
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
    property real fiveHour: 0          // current session (5h)
    property real sevenDay: 0          // weekly, all models
    property real sevenDaySonnet: 0    // weekly, Sonnet only

    // Reset timestamps (epoch ms; 0 if unknown)
    property double fiveHourReset: 0
    property double sevenDayReset: 0
    property double sevenDaySonnetReset: 0

    // ── Claude: spend (ccusage) ──────────────────────────────────────────────
    property bool spentAvailable: false
    property string spentError: ""
    // Point 2B: cache last raw ccusage payload so ModelPricing updates can
    // re-run _refineSpend without re-launching the subprocess.
    property var _lastSpendData: null

    property real spentTodayCost: 0
    property real spentWeekCost: 0
    property real spentMonthCost: 0
    property int  spentTodayTokens: 0

    // models.dev estimated cost totals
    property real spentTodayCostEstimated: 0
    property real spentWeekCostEstimated: 0
    property real spentMonthCostEstimated: 0

    // Token split totals (today only for display; week/month are aggregates)
    property int spentTodayInputTokens: 0
    property int spentTodayOutputTokens: 0
    property int spentTodayCacheTokens: 0

    property int spentWeekInputTokens: 0
    property int spentWeekOutputTokens: 0
    property int spentWeekCacheTokens: 0

    property int spentMonthInputTokens: 0
    property int spentMonthOutputTokens: 0
    property int spentMonthCacheTokens: 0

    // ── Loading flags ────────────────────────────────────────────────────────
    // Start true while the provider is enabled so the UI shows "Loading…" until
    // the first fetch resolves, instead of flashing the "unavailable" notice for
    // one frame before any fetch has run.
    property bool quotaLoading: Config.options.sidebar.aiUsage.providers.claude.enable
    property bool spentLoading: Config.options.sidebar.aiUsage.providers.claude.enable

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
        // Missing utilization → -1 ("not reported"), so the widget can hide the
        // gauge instead of drawing a misleading 0%.
        root.fiveHour           = data.five_hour?.utilization ?? -1;
        root.sevenDay           = data.seven_day?.utilization ?? -1;
        root.sevenDaySonnet     = data.seven_day_sonnet?.utilization ?? -1;
        root.fiveHourReset      = root._parseIso(data.five_hour?.resets_at);
        root.sevenDayReset      = root._parseIso(data.seven_day?.resets_at);
        root.sevenDaySonnetReset = root._parseIso(data.seven_day_sonnet?.resets_at);
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
            // Point 4: guard credentials file existence before running jq
            "creds=\"$HOME/.claude/.credentials.json\"; " +
            "if [ ! -f \"$creds\" ]; then " +
            "  echo '{\"error\":\"credentials file missing\"}'; exit 0; " +
            "fi; " +
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

    // Local YYYY-MM-DD for a Date (matches ccusage's daily `period` field).
    function _ymd(d) {
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, "0");
        const day = String(d.getDate()).padStart(2, "0");
        return `${y}-${m}-${day}`;
    }

    function _refineSpend(data) {
        // ccusage --json returns a `daily` array (one row per calendar day,
        // `period` = "YYYY-MM-DD") plus a `totals` summary. There are NO
        // weekly/monthly arrays, so today/week/month are computed by bucketing
        // the daily rows against the real calendar. A bare array of daily rows
        // is also accepted defensively.
        const rows = Array.isArray(data)
            ? data
            : (data.daily ?? data.today ?? null);

        if (!Array.isArray(rows) || rows.length === 0) {
            root.spentAvailable = false;
            root.spentError     = "unrecognized ccusage JSON shape";
            root.spentLoading   = false;
            return;
        }

        const now        = new Date();
        const todayStr   = root._ymd(now);
        // Last 7 calendar days inclusive of today.
        const weekStart  = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6);
        const curYear    = now.getFullYear();
        const curMonth   = now.getMonth();

        let todayTokens = 0, weekEstCost = 0, monthEstCost = 0, todayEstCost = 0;
        let todayInputTokens = 0, todayOutputTokens = 0, todayCacheTokens = 0;
        let weekInputTokens = 0, weekOutputTokens = 0, weekCacheTokens = 0;
        let monthInputTokens = 0, monthOutputTokens = 0, monthCacheTokens = 0;

        for (const row of rows) {
            const p = row.period ?? row.date;
            if (!p) continue;
            const d = new Date(`${p}T00:00:00`);
            if (isNaN(d.getTime())) continue;

            // Claude-only: ccusage also scans Codex/other tool logs, so sum just
            // the per-model breakdowns whose modelName starts with "claude". This
            // keeps non-Claude spend (e.g. gpt-* from Codex) out of these figures.
            // Falls back to the row total only when no breakdown is present.
            let rowEstCost = 0, tokens = 0;
            let rowInputTok = 0, rowOutputTok = 0, rowCacheTok = 0;
            const bd = row.modelBreakdowns ?? row.modelBreakdown ?? null;
            if (Array.isArray(bd) && bd.length > 0) {
                for (const mb of bd) {
                    if (!String(mb.modelName ?? "").startsWith("claude")) continue;
                    const inTok    = mb.inputTokens ?? 0;
                    const outTok   = mb.outputTokens ?? 0;
                    const cacheRd  = mb.cacheReadTokens ?? 0;
                    const cacheWr  = mb.cacheCreationTokens ?? 0;
                    const allTok   = inTok + outTok + cacheRd + cacheWr;
                    tokens += allTok;
                    rowInputTok  += inTok;
                    rowOutputTok += outTok;
                    rowCacheTok  += cacheRd + cacheWr;
                    // Use models.dev cost if available, else fall back to ccusage cost
                    const est = ModelPricing.cost("anthropic", mb.modelName ?? "", {
                        input:      inTok,
                        output:     outTok,
                        cacheRead:  cacheRd,
                        cacheWrite: cacheWr
                    });
                    rowEstCost += (est !== null) ? est : (mb.cost ?? 0);
                }
            } else {
                rowEstCost = row.totalCost ?? row.cost ?? 0;
                tokens     = row.totalTokens ?? row.tokens ?? 0;
            }

            if (p === todayStr) {
                todayEstCost      += rowEstCost;
                todayTokens       += tokens;
                todayInputTokens  += rowInputTok;
                todayOutputTokens += rowOutputTok;
                todayCacheTokens  += rowCacheTok;
            }
            if (d >= weekStart) {
                weekEstCost       += rowEstCost;
                weekInputTokens   += rowInputTok;
                weekOutputTokens  += rowOutputTok;
                weekCacheTokens   += rowCacheTok;
            }
            if (d.getFullYear() === curYear && d.getMonth() === curMonth) {
                monthEstCost      += rowEstCost;
                monthInputTokens  += rowInputTok;
                monthOutputTokens += rowOutputTok;
                monthCacheTokens  += rowCacheTok;
            }
        }

        root.spentTodayCost           = todayEstCost;
        root.spentWeekCost            = weekEstCost;
        root.spentMonthCost           = monthEstCost;
        root.spentTodayTokens         = todayTokens;
        root.spentTodayCostEstimated  = todayEstCost;
        root.spentWeekCostEstimated   = weekEstCost;
        root.spentMonthCostEstimated  = monthEstCost;
        root.spentTodayInputTokens    = todayInputTokens;
        root.spentTodayOutputTokens   = todayOutputTokens;
        root.spentTodayCacheTokens    = todayCacheTokens;

        root.spentWeekInputTokens     = weekInputTokens;
        root.spentWeekOutputTokens    = weekOutputTokens;
        root.spentWeekCacheTokens     = weekCacheTokens;

        root.spentMonthInputTokens    = monthInputTokens;
        root.spentMonthOutputTokens   = monthOutputTokens;
        root.spentMonthCacheTokens    = monthCacheTokens;

        root.spentAvailable           = true;
        root.spentError               = "";
        root.spentLoading             = false;
    }

    Process {
        id: spendFetcher
        // npx ccusage@latest --json — requires Node. On Arch, nodejs must be in
        // the PKGBUILD depends (declared in illogical-impulse-basic). If the AUR
        // ccusage package is installed, the `ccusage` binary is available directly;
        // npx falls back gracefully when it is.
        // `timeout 60` guards against a hung npx (e.g. network stall on first
        // download) leaving spentLoading stuck forever. timeout exits 124 on
        // expiry, which the onExited non-zero path handles.
        // Point 2A: try the system-installed binary first (AUR/global npm install),
        // fall back to npx without @latest so npx does NOT hit the npm registry
        // on every poll cycle. timeout 60 still guards against a hung process.
        command: ["bash", "-c", "ccusage --json 2>/dev/null || timeout 60 npx --yes ccusage --json 2>/dev/null || exit 1"]
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
                    root._lastSpendData = d;   // Point 2B: cache for pricing updates
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

    // Re-compute spend costs when ModelPricing finishes loading so costs
    // update even if pricing data arrived after the first ccusage fetch.
    // Point 2B: use the cached payload instead of re-launching the subprocess.
    Connections {
        target: ModelPricing
        function onReadyChanged() {
            if (ModelPricing.ready && root._lastSpendData) {
                root._refineSpend(root._lastSpendData);
            } else if (ModelPricing.ready) {
                // No cached data yet — pricing loaded before the first fetch;
                // fall back to a full fetch so the widget is not stuck empty.
                root._fetchSpend();
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
