# AI Usage Sidebar Tab — Design

**Date:** 2026-06-20
**Status:** Approved for planning
**Scope of this cut:** Claude only. Codex and opencode are designed-for but explicitly out of scope here.

## Problem

The user runs multiple AI coding subscriptions (Claude, OpenAI/Codex, opencode) and wants to monitor them from the Quickshell sidebar — both **how much quota is left** and **how much has been spent**. There is an upstream PR (end-4/dots-hyprland #3468) that adds Claude-only usage *gauges in the bar*, but it is cramped (two small gauges), single-provider, and configured only by hand-editing `config.json`.

We want something better: a dedicated **sidebar tab**, **multi-provider** (over time), with **per-provider toggles in the settings panel**.

## Key Design Decisions (and why)

1. **Two distinct metrics, shown per what each provider actually supports.**
   - "Remaining" (quota utilization) — only meaningful for real subscriptions.
   - "Spent" (token/cost consumption) — uniform across all providers via local logs.
   - opencode is **not** a subscription (pay-per-token with your own keys), so non-subscription providers show **spent only**. We never invent a quota that does not exist.

2. **"Spent" comes from `ccusage`, not hand-rolled parsing.**
   Cost is *computed* (tokens × per-model price), and price tables change often. `ccusage` (ryoppippi) reads the local session logs, supports Claude Code / Codex / OpenCode (14+ tools), exposes `--json`, and maintains the pricing tables. Reimplementing pricing in QML would be silent-breakage maintenance debt. We shell out to `ccusage --json` the same way the shell already shells out to `curl`/`jq`.

3. **"Remaining" is per-provider and best-effort.**
   - Claude: clean OAuth endpoint (`https://api.anthropic.com/api/oauth/usage`), token from `~/.claude/.credentials.json` — proven by PR #3468. **Solid.**
   - Codex (future): no stable `codex usage --json` yet; only obtainable by reading `~/.codex/auth.json` and calling the endpoint ourselves. Best-effort, degrades to spent-only on failure.
   - opencode: N/A.

4. **Claude first.** Claude is the only provider that is 100% solid on *both* metrics. We ship a working tab with Claude, then extend the provider model to Codex/opencode once the tab is proven live.

5. **Poll only while visible, 5-minute default, manual refresh.**
   The data barely moves unless you are actively using Claude, and each poll spawns an `npx ccusage` process plus a network call. So: fetch on tab-open, repeat on `fetchInterval` (default 5 min, configurable) **only while the tab is visible**, plus click-to-refresh-now. No polling when the panel is closed.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Settings panel (ServicesConfig.qml)                          │
│   ConfigSwitch per provider  →  Config.options.sidebar.aiUsage│
└───────────────────────────┬─────────────────────────────────┘
                            │ reads config
┌───────────────────────────▼─────────────────────────────────┐
│ AiUsage.qml  (Singleton service, services/)                  │
│   - Timer (gated on tab-visible + enabled providers)         │
│   - per-provider fetch:                                      │
│       claude.remaining → curl OAuth endpoint (token file)    │
│       claude.spent     → npx ccusage --json                  │
│   - exposes reactive properties + available/error per metric │
└───────────────────────────┬─────────────────────────────────┘
                            │ binds properties
┌───────────────────────────▼─────────────────────────────────┐
│ AiUsageWidget.qml  (sidebar tab, sidebarRight/aiUsage/)      │
│   - one card per enabled provider                            │
│   - Claude card: quota gauges (5h / 7d) + spent block        │
│   - graceful per-card error/empty states                     │
│   - sets AiUsage.tabVisible while shown                      │
└─────────────────────────────────────────────────────────────┘
   registered as a tab in BottomWidgetGroup.qml (sibling of Calendar/To Do/Timer)
```

### Components

**`services/AiUsage.qml`** — Singleton, follows the `Weather.qml` / `ResourceUsage.qml` pattern (Singleton + Timer + `Process`/`StdioCollector`).
- Inputs: `Config.options.sidebar.aiUsage` (master `enable`, `fetchInterval`, `warningThreshold`, `providers.claude.enable`).
- State exposed (Claude cut):
  - `claudeAvailable: bool`, `claudeError: string`
  - Remaining: `fiveHour`, `sevenDay` (0–100), `fiveHourReset`, `sevenDayReset` (epoch ms), `subscriptionType`
  - Spent: `spentTodayCost`, `spentWeekCost`, `spentMonthCost`, `spentTodayTokens` (from `ccusage --json`)
  - `spentAvailable: bool` (false if `ccusage` missing)
- `tabVisible: bool` — set by the widget; Timer only runs when `enabled && tabVisible`.
- `refresh()` — manual, called on click.
- Designed for extension: provider logic is keyed so Codex/opencode slot in later without reshaping the service.

**`modules/ii/sidebarRight/aiUsage/AiUsageWidget.qml`** — the tab content.
- A column of provider cards (only Claude in this cut).
- Claude card:
  - Header: "Claude" + subscription type.
  - Quota: two `ClippedFilledCircularProgress` gauges (5h session, 7d week), red past `warningThreshold`, reset countdown text. Reuses widgets from the PR / existing `Resources` style.
  - Spent: today / week / month cost + today tokens.
  - States: loading; quota-unavailable (show spent only); ccusage-missing (show quota only + install hint); fully-unavailable (friendly message).
- Sets `AiUsage.tabVisible = true` on show, `false` on hide.

**`modules/ii/sidebarRight/BottomWidgetGroup.qml`** — add one entry to the `tabs` array:
`{ type: "aiUsage", name: Translation.tr("AI Usage"), icon: "monitoring", widget: "aiUsage/AiUsageWidget.qml" }`.

**`modules/common/Config.qml`** — add under `sidebar`:
```qml
property JsonObject aiUsage: JsonObject {
    property bool enable: false
    property int fetchInterval: 5      // minutes
    property int warningThreshold: 90  // % → gauge turns red
    property JsonObject providers: JsonObject {
        property JsonObject claude: JsonObject { property bool enable: false }
    }
}
```

**`modules/settings/ServicesConfig.qml`** — a small "AI Usage" section: master enable + a `ConfigSwitch` for Claude (Codex/opencode toggles added with their providers later).

## Data Flow

1. Tab opens → `AiUsage.tabVisible = true` → immediate `refresh()`.
2. `refresh()` (only for enabled providers):
   - Claude remaining: read token from `~/.claude/.credentials.json`, `curl` the OAuth usage endpoint, parse → `fiveHour`/`sevenDay`/resets/`subscriptionType`.
   - Claude spent: run `npx ccusage@latest --json` (daily/weekly/monthly), parse Claude rows → cost/token properties.
3. Timer re-runs every `fetchInterval` minutes **while visible**.
4. Click on card → `refresh()` now.
5. Tab hides → `tabVisible = false` → Timer stops.

## Error Handling / Degradation

| Failure | Behavior |
|---|---|
| `ccusage` not installed | Spent block hidden, one-line install hint; quota still shown |
| OAuth token missing / endpoint fails | Quota hidden ("quota unavailable"); spent still shown |
| Both fail | Card shows a single friendly "unavailable" message with the last error |
| Provider disabled | Card not rendered; not polled |
| Panel/tab closed | No polling at all |

Each provider fails in isolation — one broken source never blanks the tab.

## Out of Scope (this cut)

- Codex and opencode providers (service is structured to accept them; not implemented).
- Codex "remaining" endpoint reverse-engineering.
- Historical charts / graphs of spend over time.
- Notifications/alerts when crossing the threshold (gauge color only).

## Verification

This is QML/Quickshell shell config; the repo has **no UI test runner**. Verification is **manual on the live shell**, documented as a checklist:

1. Toggle off (default): tab does not appear / no polling; nothing changes for existing users.
2. Toggle on + Claude enabled: tab appears, quota gauges and spent populate within one cycle.
3. `ccusage` absent: spent hint shown, quota still works.
4. Token file absent / network down: quota-unavailable, spent still works.
5. Threshold: gauge turns red at/above `warningThreshold`.
6. Visibility: confirm no polling while the tab/panel is closed (e.g. observe no `ccusage`/`curl` processes).
7. Manual refresh: click updates immediately.

No "tests pass" claim will be made where no tests exist — only the observed results of this checklist.

## Files Touched

| File | Change |
|---|---|
| `dots/.config/quickshell/ii/services/AiUsage.qml` | **new** — usage service singleton |
| `dots/.config/quickshell/ii/modules/ii/sidebarRight/aiUsage/AiUsageWidget.qml` | **new** — tab content |
| `dots/.config/quickshell/ii/modules/ii/sidebarRight/BottomWidgetGroup.qml` | add tab entry |
| `dots/.config/quickshell/ii/modules/common/Config.qml` | add `sidebar.aiUsage` config |
| `dots/.config/quickshell/ii/modules/settings/ServicesConfig.qml` | add AI Usage settings section |

## References

- Upstream PR: end-4/dots-hyprland #3468 (Claude bar gauges) — source for the OAuth endpoint + gauge widgets.
- `ccusage` — https://github.com/ryoppippi/ccusage (spent, `--json`, multi-provider).
- Claude OAuth usage endpoint: `https://api.anthropic.com/api/oauth/usage`, token at `~/.claude/.credentials.json`.
