pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: rootBlock
    
    // --- Public Properties ---
    property string title: ""
    property var rows: []
    property bool expanded: false
    
    readonly property real totalCost: {
        let sum = 0;
        if (rows) {
            for (let i = 0; i < rows.length; i++) {
                let c = rows[i].estimatedCost;
                if (typeof c === "number" && !isNaN(c)) sum += c;
            }
        }
        return sum;
    }

    readonly property int totalTokens: {
        let sum = 0;
        if (rows) {
            for (let i = 0; i < rows.length; i++) {
                let t = rows[i].tokens;
                if (typeof t === "number" && !isNaN(t)) sum += t;
            }
        }
        return sum;
    }
    
    visible: rows && rows.length > 0
    Layout.fillWidth: true
    spacing: 4
    
    function formatCost(v) {
        if (typeof v !== "number" || isNaN(v)) return "$0.00";
        return "$" + v.toFixed(2);
    }
    
    function formatTokens(n) {
        if (typeof n !== "number" || isNaN(n)) return "0";
        if (n >= 1_000_000) return parseFloat((n / 1_000_000).toFixed(1)) + "M";
        if (n >= 1_000)     return parseFloat((n / 1_000).toFixed(1)) + "k";
        return String(n);
    }

    // --- Collapsible Header Row ---
    Rectangle {
        id: headerRect
        Layout.fillWidth: true
        implicitHeight: headerRow.implicitHeight + 12
        radius: Appearance.rounding.small
        color: headerMouseArea.containsMouse ? Appearance.colors.colLayer3 : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }

        MouseArea {
            id: headerMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rootBlock.expanded = !rootBlock.expanded
        }

        RowLayout {
            id: headerRow
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 6
                rightMargin: 6
            }
            spacing: 6

            MaterialSymbol {
                text: "keyboard_arrow_right"
                iconSize: Appearance.font.pixelSize.large
                color: headerMouseArea.containsMouse ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                rotation: rootBlock.expanded ? 90 : 0
                Behavior on rotation {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: headerMouseArea.containsMouse ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                text: rootBlock.title
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
                text: rootBlock.formatCost(rootBlock.totalCost)
            }
        }
    }

    // --- Expanded Content ---
    ColumnLayout {
        id: contentCol
        visible: rootBlock.expanded
        Layout.fillWidth: true
        Layout.leftMargin: 20
        Layout.rightMargin: 4
        Layout.topMargin: 2
        Layout.bottomMargin: 4
        spacing: 4

        Repeater {
            model: rootBlock.rows
            delegate: ColumnLayout {
                id: rowCol
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 2

                property bool isHovered: hoverHandler.hovered

                // Divider between models (skipped before the first row)
                Rectangle {
                    visible: rowCol.index > 0
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    Layout.preferredHeight: 1
                    color: Appearance.colors.colOutlineVariant
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: rowCol.isHovered ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        text: (modelData.model ?? "unknown")
                        elide: Text.ElideRight
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                        text: modelData.estimatedCost != null
                            ? rootBlock.formatCost(modelData.estimatedCost)
                            : "—"
                    }
                    
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        text: rootBlock.formatTokens(modelData.tokens ?? 0)
                               + " " + Translation.tr("tokens")
                    }
                }
                
                RowLayout {
                    visible: (modelData.tok_input !== undefined) || (modelData.tok_output !== undefined)
                    Layout.alignment: Qt.AlignRight
                    spacing: 4

                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: rootBlock.formatTokens(modelData.tok_input ?? 0) + " in · "
                            + rootBlock.formatTokens((modelData.tok_output ?? 0) + (modelData.tok_reasoning ?? 0)) + " out · "
                            + rootBlock.formatTokens((modelData.tok_cache_read ?? 0) + (modelData.tok_cache_write ?? 0)) + " cache"
                    }
                }
                
                HoverHandler {
                    id: hoverHandler
                }
            }
        }
    }
}
