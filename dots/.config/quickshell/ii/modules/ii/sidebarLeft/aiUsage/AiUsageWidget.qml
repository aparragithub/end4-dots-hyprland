pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

/**
 * AI Usage sidebar tab content.
 *
 * Sets AiUsage.tabVisible = true while mounted so the service polls; resets on
 * destruction to stop polling. Click-to-refresh is wired on the card header.
 *
 * Degradation matrix (per-source, independent):
 *   quota unavailable  → quota section hidden, "quota unavailable" notice shown
 *   ccusage missing    → spend block hidden, one-line install hint shown
 *   both unavailable   → single friendly "unavailable" message
 *   loading            → per-section loading indicator
 */
Item {
    id: root

    // The left-sidebar SwipeView instantiates every tab up front, so gate the
    // service on whether THIS tab is the visible one — otherwise polling would
    // start as soon as the sidebar opens, regardless of the active tab.
    property bool active: SwipeView.view ? SwipeView.isCurrentItem : visible

    // Whether at least one AI provider is enabled in config
    readonly property bool anyProviderEnabled:
        Config.options.sidebar.aiUsage.providers.claude.enable
        || Config.options.sidebar.aiUsage.providers.openai.enable
        || Config.options.sidebar.aiUsage.providers.antigravity.enable
        || Config.options.sidebar.aiUsage.providers.opencode.enable

    // Fan-out tabVisible to all four provider services. Each service self-gates
    // on its own enable flag, so setting tabVisible on a disabled service is safe.
    onActiveChanged: {
        AiUsage.tabVisible          = root.active;
        OpenAiUsage.tabVisible      = root.active;
        AntigravityUsage.tabVisible = root.active;
        OpenCodeUsage.tabVisible    = root.active;
    }
    Component.onCompleted: {
        AiUsage.tabVisible          = root.active;
        OpenAiUsage.tabVisible      = root.active;
        AntigravityUsage.tabVisible = root.active;
        OpenCodeUsage.tabVisible    = root.active;
    }
    Component.onDestruction: {
        AiUsage.tabVisible          = false;
        OpenAiUsage.tabVisible      = false;
        AntigravityUsage.tabVisible = false;
        OpenCodeUsage.tabVisible    = false;
    }

    // ── Helper: format cost as whole dollars, always rounded up ──────────────
    function formatCost(v) {
        if (typeof v !== "number" || isNaN(v)) return "$0";
        return "$" + Math.ceil(v);
    }

    // ── Helper: format token count with 1 decimal place ──────────────────────
    // Uses toFixed(1) + parseFloat to avoid the Math.ceil over-rounding bug.
    function formatTokens(n) {
        if (typeof n !== "number" || isNaN(n)) return "0";
        if (n >= 1_000_000) return parseFloat((n / 1_000_000).toFixed(1)) + "M";
        if (n >= 1_000)     return parseFloat((n / 1_000).toFixed(1)) + "k";
        return String(n);
    }

    ScrollView {
        anchors.fill: parent
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: root.width
            spacing: 12

            // ── Padding top ──────────────────────────────────────────────────
            Item { Layout.preferredHeight: 4 }

            // ── No providers enabled message ─────────────────────────────────

            StyledText {
                visible: !root.anyProviderEnabled
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.normal
                text: Translation.tr("No AI provider is enabled. Go to Settings → Services to activate one.")
            }

            // ── Claude card ──────────────────────────────────────────────────
            AiProviderCard {
                id: claudeCard
                visible: Config.options.sidebar.aiUsage.providers.claude.enable
                title: AiUsage.subscriptionType.length > 0
                    ? "Claude " + AiUsage.subscriptionType.charAt(0).toUpperCase()
                                 + AiUsage.subscriptionType.slice(1)
                    : "Claude"
                iconName: "auto_awesome"
                service: AiUsage
                accentColor: Appearance.colors.colPrimary
                
                // Determine display mode
                property bool quotaOk: AiUsage.claudeAvailable && !AiUsage.claudeError
                property bool spentOk: AiUsage.spentAvailable  && !AiUsage.spentError
                
                bothFail: !quotaOk && !spentOk && !AiUsage.quotaLoading && !AiUsage.spentLoading
                bothFailMessage: Translation.tr("Usage data unavailable. Check your Claude token and that Node.js is installed.")
                forceContentVisible: !bothFail
                
                // Custom Content Slot
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    
                    // ── Quota section ────────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        
                        // Loading indicator for quota
                        StyledText {
                            visible: AiUsage.quotaLoading && !AiUsage.claudeAvailable
                            Layout.alignment: Qt.AlignHCenter
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: Translation.tr("Loading quota…")
                        }
                        
                        // Quota unavailable notice
                        StyledText {
                            visible: !AiUsage.quotaLoading
                                  && !AiUsage.claudeAvailable
                                  && !claudeCard.bothFail
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: Translation.tr("Quota unavailable") +
                                  (AiUsage.claudeError.length > 0 ? ": " + AiUsage.claudeError : "")
                        }
                        
                        // Quota gauges row (5h + 7d)
                        RowLayout {
                            visible: AiUsage.claudeAvailable
                            Layout.fillWidth: true
                            spacing: 20
                            
                            Item { Layout.fillWidth: true }
                            
                            AiQuotaGauge {
                                visible: AiUsage.fiveHour >= 0
                                valuePercent: AiUsage.fiveHour
                                title: Translation.tr("Session (5h)")
                                subtitle: AiUsage.timeUntil(AiUsage.fiveHourReset)
                            }
                            
                            AiQuotaGauge {
                                visible: AiUsage.sevenDay >= 0
                                valuePercent: AiUsage.sevenDay
                                title: Translation.tr("Week · All")
                                subtitle: AiUsage.timeUntil(AiUsage.sevenDayReset)
                            }
                            
                            AiQuotaGauge {
                                visible: AiUsage.sevenDaySonnet >= 0
                                valuePercent: AiUsage.sevenDaySonnet
                                title: Translation.tr("Week · Sonnet")
                                subtitle: AiUsage.timeUntil(AiUsage.sevenDaySonnetReset)
                            }
                            
                            Item { Layout.fillWidth: true }
                        }
                    }
                    
                    // ── Divider between quota and spend ──────────────────────
                    Rectangle {
                        visible: AiUsage.claudeAvailable
                              || (AiUsage.spentAvailable && !claudeCard.bothFail)
                        Layout.fillWidth: true
                        height: 1
                        color: Appearance.colors.colLayer3
                    }
                    
                    // ── Spend section ────────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        
                        // Loading indicator for spend
                        StyledText {
                            visible: AiUsage.spentLoading && !AiUsage.spentAvailable
                            Layout.alignment: Qt.AlignHCenter
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: Translation.tr("Loading spend…")
                        }
                        
                        // ccusage-missing install hint
                        StyledText {
                            visible: !AiUsage.spentLoading
                                  && !AiUsage.spentAvailable
                                  && !claudeCard.bothFail
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: Translation.tr("Spend unavailable. Install ccusage: yay -S ccusage (npx fallback used automatically)")
                        }
                        
                        // Spend Table
                        AiSpendTable {
                            visible: AiUsage.spentAvailable
                            todayCost: AiUsage.spentTodayCost
                            todayTokensText: root.formatTokens(AiUsage.spentTodayInputTokens) + " in · "
                                + root.formatTokens(AiUsage.spentTodayOutputTokens) + " out · "
                                + root.formatTokens(AiUsage.spentTodayCacheTokens) + " cache"
                            weekCost: AiUsage.spentWeekCost
                            weekTokensText: root.formatTokens(AiUsage.spentWeekInputTokens) + " in · "
                                + root.formatTokens(AiUsage.spentWeekOutputTokens) + " out · "
                                + root.formatTokens(AiUsage.spentWeekCacheTokens) + " cache"
                            monthCost: AiUsage.spentMonthCost
                            monthTokensText: root.formatTokens(AiUsage.spentMonthInputTokens) + " in · "
                                + root.formatTokens(AiUsage.spentMonthOutputTokens) + " out · "
                                + root.formatTokens(AiUsage.spentMonthCacheTokens) + " cache"
                        }
                    }
                }
            }

            // ── OpenCode card ────────────────────────────────────────────────
            AiProviderCard {
                id: opencodeCard
                visible: Config.options.sidebar.aiUsage.providers.opencode.enable
                title: "OpenCode"
                iconName: "code_blocks"
                service: OpenCodeUsage
                accentColor: Appearance.colors.colPrimary
                
                isLoading: OpenCodeUsage.usageLoading
                isAvailable: OpenCodeUsage.available && !OpenCodeUsage.error
                errorMessage: OpenCodeUsage.error.length > 0 ? OpenCodeUsage.error : Translation.tr("Usage unavailable")
                
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                        text: Translation.tr("Estimated API-rate cost")
                    }
                    
                    AiOpenCodePeriodBlock {
                        title: Translation.tr("Today")
                        rows: OpenCodeUsage.todayRows
                    }
                    
                    Rectangle {
                        visible: OpenCodeUsage.todayRows.length > 0 && OpenCodeUsage.weekRows.length > 0
                        Layout.fillWidth: true
                        height: 1
                        color: Appearance.colors.colLayer3
                    }
                    
                    AiOpenCodePeriodBlock {
                        title: Translation.tr("This week")
                        rows: OpenCodeUsage.weekRows
                    }
                    
                    Rectangle {
                        visible: OpenCodeUsage.weekRows.length > 0 && OpenCodeUsage.monthRows.length > 0
                        Layout.fillWidth: true
                        height: 1
                        color: Appearance.colors.colLayer3
                    }
                    
                    AiOpenCodePeriodBlock {
                        title: Translation.tr("This month")
                        rows: OpenCodeUsage.monthRows
                    }
                }
            }

            // ── Codex (OpenAI) card ──────────────────────────────────────────
            AiProviderCard {
                id: codexCard
                visible: Config.options.sidebar.aiUsage.providers.openai.enable
                title: OpenAiUsage.subscriptionType.length > 0
                    ? "Codex " + OpenAiUsage.subscriptionType.charAt(0).toUpperCase()
                                 + OpenAiUsage.subscriptionType.slice(1)
                    : "Codex"
                iconName: "terminal"
                service: OpenAiUsage
                accentColor: Appearance.colors.colPrimary
                
                isLoading: OpenAiUsage.usageLoading
                isAvailable: OpenAiUsage.available && !OpenAiUsage.error
                errorMessage: OpenAiUsage.error.length > 0 ? OpenAiUsage.error : Translation.tr("Usage unavailable")
                
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    
                    // Quota gauges row (5h + 7d)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 20
                        
                        Item { Layout.fillWidth: true }
                        
                        AiQuotaGauge {
                            visible: OpenAiUsage.fiveHour >= 0
                            valuePercent: OpenAiUsage.fiveHour
                            title: Translation.tr("Session (5h)")
                            subtitle: OpenAiUsage.timeUntil(OpenAiUsage.fiveHourReset)
                        }
                        
                        AiQuotaGauge {
                            visible: OpenAiUsage.sevenDay >= 0
                            valuePercent: OpenAiUsage.sevenDay
                            title: Translation.tr("Week · All")
                            subtitle: OpenAiUsage.timeUntil(OpenAiUsage.sevenDayReset)
                        }
                        
                        Item { Layout.fillWidth: true }
                    }
                    
                    // Divider
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Appearance.colors.colLayer3
                    }
                    
                    // Spend Table
                    AiSpendTable {
                        title: Translation.tr("Estimated API-rate cost")
                        todayCost: OpenAiUsage.spentTodayCost
                        todayTokensText: root.formatTokens(OpenAiUsage.spentTodayInputTokens) + " in · "
                            + root.formatTokens(OpenAiUsage.spentTodayOutputTokens) + " out · "
                            + root.formatTokens(OpenAiUsage.spentTodayCacheTokens) + " cache"
                        weekCost: OpenAiUsage.spentWeekCost
                        weekTokensText: root.formatTokens(OpenAiUsage.spentWeekTokens) + " " + Translation.tr("tokens")
                        monthCost: OpenAiUsage.spentMonthCost
                        monthTokensText: root.formatTokens(OpenAiUsage.spentMonthTokens) + " " + Translation.tr("tokens")
                    }
                }
            }

            // ── Antigravity card ─────────────────────────────────────────────
            AiProviderCard {
                id: antigravityCard
                visible: Config.options.sidebar.aiUsage.providers.antigravity.enable
                title: "Antigravity"
                iconName: "auto_awesome_motion"
                service: AntigravityUsage
                accentColor: Appearance.colors.colPrimary
                
                isLoading: AntigravityUsage.usageLoading
                isAvailable: AntigravityUsage.available && !AntigravityUsage.error
                errorMessage: AntigravityUsage.error.length > 0 ? AntigravityUsage.error : Translation.tr("Quota unavailable")
                
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    
                    Repeater {
                        model: AntigravityUsage.groups
                        
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                                text: modelData.name
                                elide: Text.ElideRight
                            }
                            
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 20

                                Item { Layout.fillWidth: true }

                                Repeater {
                                    model: modelData.buckets
                                    
                                    delegate: AiQuotaGauge {
                                        required property var modelData
                                        valuePercent: modelData.usedPercent
                                        title: modelData.displayName
                                        subtitle: modelData.resetTime
                                            ? AntigravityUsage.timeUntil(new Date(modelData.resetTime).getTime())
                                            : "—"
                                    }
                                }
                                
                                Item { Layout.fillWidth: true }
                            }
                        }
                    }
                }
            }

            // ── Bottom padding ───────────────────────────────────────────────
            Item { Layout.preferredHeight: 8 }
        }
    }
}
