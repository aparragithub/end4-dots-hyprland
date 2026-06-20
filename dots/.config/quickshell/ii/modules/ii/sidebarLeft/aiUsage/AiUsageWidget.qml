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
    onActiveChanged: AiUsage.tabVisible = root.active
    Component.onCompleted:   { AiUsage.tabVisible = root.active; }
    Component.onDestruction: { AiUsage.tabVisible = false; }

    // ── Helper: format cost as whole dollars, always rounded up ──────────────
    function formatCost(v) {
        if (typeof v !== "number" || isNaN(v)) return "$0";
        return "$" + Math.ceil(v);
    }

    // ── Helper: format token count (no decimals, rounded up) ─────────────────
    function formatTokens(n) {
        if (typeof n !== "number" || isNaN(n)) return "0";
        if (n >= 1_000_000) return Math.ceil(n / 1_000_000) + "M";
        if (n >= 1_000)     return Math.ceil(n / 1_000) + "k";
        return String(n);
    }

    ScrollView {
        anchors.fill: parent
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: root.width
            spacing: 10

            // ── Padding top ──────────────────────────────────────────────────
            Item { Layout.preferredHeight: 4 }

            // ── Claude card ──────────────────────────────────────────────────
            Rectangle {
                id: claudeCard
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2
                implicitHeight: claudeCardColumn.implicitHeight + 24

                // Determine display mode
                property bool quotaOk:   AiUsage.claudeAvailable && !AiUsage.claudeError
                property bool spentOk:   AiUsage.spentAvailable  && !AiUsage.spentError
                property bool bothFail:  !quotaOk && !spentOk && !AiUsage.quotaLoading && !AiUsage.spentLoading

                ColumnLayout {
                    id: claudeCardColumn
                    anchors {
                        left: parent.left; right: parent.right
                        top: parent.top
                        margins: 12
                    }
                    spacing: 10

                    // ── Card header ──────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: "auto_awesome"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                            text: AiUsage.subscriptionType.length > 0
                                ? "Claude " + AiUsage.subscriptionType.charAt(0).toUpperCase()
                                             + AiUsage.subscriptionType.slice(1)
                                : "Claude"
                        }

                        // Refresh button
                        MouseArea {
                            id: refreshArea
                            implicitWidth: 28
                            implicitHeight: 28
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: AiUsage.refresh()

                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.small
                                color: refreshArea.containsMouse
                                    ? Appearance.colors.colLayer3
                                    : "transparent"
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "refresh"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }

                    // ── Both-fail state ──────────────────────────────────────
                    StyledText {
                        visible: claudeCard.bothFail
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: Translation.tr("Usage data unavailable. Check your Claude token and that Node.js is installed.")
                    }

                    // ── Quota section ────────────────────────────────────────
                    ColumnLayout {
                        visible: !claudeCard.bothFail
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

                            // ── 5-hour gauge ─────────────────────────────────
                            ColumnLayout {
                                // -1 means "not reported by the API" → hide the
                                // gauge rather than drawing a misleading 0%.
                                visible: AiUsage.fiveHour >= 0
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 4

                                ClippedFilledCircularProgress {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitSize: 64
                                    lineWidth: 4
                                    enableAnimation: true
                                    value: Math.max(0, Math.min(1, AiUsage.fiveHour / 100))
                                    colPrimary: AiUsage.fiveHour >= Config.options.sidebar.aiUsage.warningThreshold
                                        ? Appearance.colors.colError
                                        : Appearance.colors.colPrimary
                                    accountForLightBleeding: AiUsage.fiveHour < Config.options.sidebar.aiUsage.warningThreshold

                                    // Centered percentage text (replaces default text mask)
                                    Item {
                                        width: 64; height: 64
                                        StyledText {
                                            anchors.centerIn: parent
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Medium
                                            color: Appearance.colors.colOnLayer1
                                            text: Math.round(AiUsage.fiveHour) + "%"
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                    text: Translation.tr("Session (5h)")
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    text: AiUsage.timeUntil(AiUsage.fiveHourReset)
                                }
                            }

                            // ── 7-day gauge ──────────────────────────────────
                            ColumnLayout {
                                // -1 means "not reported by the API" → hide the
                                // gauge rather than drawing a misleading 0%.
                                visible: AiUsage.sevenDay >= 0
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 4

                                ClippedFilledCircularProgress {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitSize: 64
                                    lineWidth: 4
                                    enableAnimation: true
                                    value: Math.max(0, Math.min(1, AiUsage.sevenDay / 100))
                                    colPrimary: AiUsage.sevenDay >= Config.options.sidebar.aiUsage.warningThreshold
                                        ? Appearance.colors.colError
                                        : Appearance.colors.colPrimary
                                    accountForLightBleeding: AiUsage.sevenDay < Config.options.sidebar.aiUsage.warningThreshold

                                    Item {
                                        width: 64; height: 64
                                        StyledText {
                                            anchors.centerIn: parent
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Medium
                                            color: Appearance.colors.colOnLayer1
                                            text: Math.round(AiUsage.sevenDay) + "%"
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                    text: Translation.tr("Week · All")
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    text: AiUsage.timeUntil(AiUsage.sevenDayReset)
                                }
                            }

                            // ── 7-day Sonnet gauge ───────────────────────────
                            ColumnLayout {
                                // -1 means "not reported by the API" → hide the
                                // gauge rather than drawing a misleading 0%.
                                visible: AiUsage.sevenDaySonnet >= 0
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 4

                                ClippedFilledCircularProgress {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitSize: 64
                                    lineWidth: 4
                                    enableAnimation: true
                                    value: Math.max(0, Math.min(1, AiUsage.sevenDaySonnet / 100))
                                    colPrimary: AiUsage.sevenDaySonnet >= Config.options.sidebar.aiUsage.warningThreshold
                                        ? Appearance.colors.colError
                                        : Appearance.colors.colPrimary
                                    accountForLightBleeding: AiUsage.sevenDaySonnet < Config.options.sidebar.aiUsage.warningThreshold

                                    Item {
                                        width: 64; height: 64
                                        StyledText {
                                            anchors.centerIn: parent
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Medium
                                            color: Appearance.colors.colOnLayer1
                                            text: Math.round(AiUsage.sevenDaySonnet) + "%"
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                    text: Translation.tr("Week · Sonnet")
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    text: AiUsage.timeUntil(AiUsage.sevenDaySonnetReset)
                                }
                            }
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
                        visible: !claudeCard.bothFail
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

                        // Spend table: label | cost | tokens, columns aligned so
                        // each value sits under its own column. Rows without a
                        // token figure leave the tokens cell empty.
                        ColumnLayout {
                            visible: AiUsage.spentAvailable
                            Layout.fillWidth: true
                            spacing: 4

                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                                text: Translation.tr("Spend")
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 3
                                columnSpacing: 16
                                rowSpacing: 4

                                // ── Today ─────────────────────────────────────
                                StyledText {
                                    Layout.fillWidth: true
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                    text: Translation.tr("Today")
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                    text: root.formatCost(AiUsage.spentTodayCost)
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                    text: root.formatTokens(AiUsage.spentTodayTokens)
                                           + " " + Translation.tr("tokens")
                                }

                                // ── This week ─────────────────────────────────
                                StyledText {
                                    Layout.fillWidth: true
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                    text: Translation.tr("This week")
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                    text: root.formatCost(AiUsage.spentWeekCost)
                                }
                                StyledText { text: "" }

                                // ── This month ────────────────────────────────
                                StyledText {
                                    Layout.fillWidth: true
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                    text: Translation.tr("This month")
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                    text: root.formatCost(AiUsage.spentMonthCost)
                                }
                                StyledText { text: "" }
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
