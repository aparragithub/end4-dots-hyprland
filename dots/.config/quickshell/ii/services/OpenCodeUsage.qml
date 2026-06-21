pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

/**
 * OpenCode usage service — real per-token spend, multi-provider.
 *
 * Data source: SQLite DB at ~/.local/share/opencode/opencode.db (WAL mode).
 * Table: message — column data (TEXT, JSON per message). Assistant messages
 * carry the spend at top level: modelID, providerID, cost (USD), and
 * tokens.total. time_created is epoch MILLISECONDS.
 *
 * We group by MODEL (json_extract(data,'$.modelID')) so distinct models like
 * deepseek, gpt, kimi show as separate rows, with their providerID alongside.
 * Aggregation: three grouped queries (today / week / month) emitted as a
 * single JSON object by one sqlite3 invocation.
 *
 * Cost is real (billed at token rates) — NOT estimated. Do not label it
 * "estimated" in the widget.
 *
 * Polling: visibility-gated — only when tabVisible && opencode.enable.
 *
 * Degradation:
 *   DB missing    -> available=false, error="no OpenCode usage data"
 *   sqlite3 CLI missing -> available=false, error hints install
 */
Singleton {
    id: root

    // ── Visibility gate ──────────────────────────────────────────────────────
    property bool tabVisible: false

    // ── Data properties ──────────────────────────────────────────────────────
    property bool available: false
    property string error: ""

    // Per-period arrays: each element is { model, provider, cost, tokens }
    property var todayRows: []
    property var weekRows: []
    property var monthRows: []

    // Period totals (sum across all providers)
    property real spentTodayCost: 0
    property real spentWeekCost: 0
    property real spentMonthCost: 0
    property int spentTodayTokens: 0
    property int spentWeekTokens: 0
    property int spentMonthTokens: 0

    // ── Loading flag ─────────────────────────────────────────────────────────
    property bool usageLoading: Config.options.sidebar.aiUsage.providers.opencode.enable

    // ── Fetch pipeline ───────────────────────────────────────────────────────
    function _fetch() {
        if (!Config.options.sidebar.aiUsage.providers.opencode.enable) return;
        if (fetcher.running) return;
        root.usageLoading = true;
        fetcher.running = true;
    }

    function _parse(data) {
        if (data.error) {
            root.available    = false;
            root.error        = String(data.error);
            root.usageLoading = false;
            return;
        }

        const todayArr = data.today ?? [];
        const weekArr  = data.week  ?? [];
        const monthArr = data.month ?? [];

        root.todayRows = todayArr;
        root.weekRows  = weekArr;
        root.monthRows = monthArr;

        let tc = 0, tt = 0;
        for (const r of todayArr) { tc += r.cost ?? 0; tt += r.tokens ?? 0; }
        root.spentTodayCost   = tc;
        root.spentTodayTokens = tt;

        let wc = 0, wt = 0;
        for (const r of weekArr) { wc += r.cost ?? 0; wt += r.tokens ?? 0; }
        root.spentWeekCost   = wc;
        root.spentWeekTokens = wt;

        let mc = 0, mt = 0;
        for (const r of monthArr) { mc += r.cost ?? 0; mt += r.tokens ?? 0; }
        root.spentMonthCost   = mc;
        root.spentMonthTokens = mt;

        root.available    = true;
        root.error        = "";
        root.usageLoading = false;
    }

    Process {
        id: fetcher
        // One sqlite3 invocation emits a JSON object with three keys:
        // today, week, month — each an array of {provider, cost, tokens}.
        // Period boundaries computed via `date` (epoch ms).
        // DB is opened read-only (mode=ro URI parameter).
        // IMPORTANT: the jq string uses single-char field references only;
        // no block-comment-unsafe sequences appear here.
        command: [
            "bash", "-c",
            "db=\"$HOME/.local/share/opencode/opencode.db\"; " +
            "if ! command -v sqlite3 >/dev/null 2>&1; then " +
            "  echo '{\"error\":\"sqlite3 not found — install sqlite\"}'; exit 0; " +
            "fi; " +
            "if [ ! -f \"$db\" ]; then " +
            "  echo '{\"error\":\"no OpenCode usage data (~/.local/share/opencode/opencode.db not found)\"}'; exit 0; " +
            "fi; " +
            "t0=$(date -d 'today 00:00' +%s 2>/dev/null || date -v0H -v0M -v0S +%s)000; " +
            "w0=$(date -d '7 days ago 00:00' +%s 2>/dev/null || date -v-7d -v0H -v0M -v0S +%s)000; " +
            "m0=$(date -d 'this month 00:00' +%s 2>/dev/null || date -v1d -v0H -v0M -v0S +%s)000; " +
            "sel=\"SELECT json_extract(data,'$.modelID') AS model, json_extract(data,'$.providerID') AS provider, ROUND(SUM(COALESCE(json_extract(data,'$.cost'),0)),6) AS cost, CAST(SUM(COALESCE(json_extract(data,'$.tokens.total'),0)) AS INTEGER) AS tokens FROM message WHERE json_extract(data,'$.modelID') IS NOT NULL\"; " +
            "q_today=\"$sel AND time_created >= $t0 GROUP BY provider, model ORDER BY cost DESC\"; " +
            "q_week=\"$sel AND time_created >= $w0 GROUP BY provider, model ORDER BY cost DESC\"; " +
            "q_month=\"$sel AND time_created >= $m0 GROUP BY provider, model ORDER BY cost DESC\"; " +
            "today_json=$(sqlite3 -json \"file:${db}?mode=ro\" \"$q_today\" 2>/dev/null); today_json=${today_json:-[]}; " +
            "week_json=$(sqlite3  -json \"file:${db}?mode=ro\" \"$q_week\"  2>/dev/null); week_json=${week_json:-[]}; " +
            "month_json=$(sqlite3 -json \"file:${db}?mode=ro\" \"$q_month\" 2>/dev/null); month_json=${month_json:-[]}; " +
            "printf '{\"today\":%s,\"week\":%s,\"month\":%s}' \"$today_json\" \"$week_json\" \"$month_json\""
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                root.usageLoading = false;
                const raw = text.trim();
                if (raw.length === 0) {
                    root.available = false;
                    root.error = "no output from sqlite3";
                    return;
                }
                try {
                    const d = JSON.parse(raw);
                    root._parse(d);
                } catch (e) {
                    root.available = false;
                    root.error = e.message;
                    console.error(`[OpenCodeUsage] ${e.message}: ${raw.substring(0, 200)}`);
                }
            }
        }
        onExited: (code, _signal) => {
            if (code !== 0) {
                root.usageLoading = false;
                root.available    = false;
                root.error        = `sqlite3 exited with code ${code}`;
            }
        }
    }

    // ── Public API ───────────────────────────────────────────────────────────
    function refresh() {
        root._fetch();
    }

    // ── Visibility-gated Timer ───────────────────────────────────────────────
    property bool _anyEnabled: Config.options.sidebar.aiUsage.providers.opencode.enable

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
