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
    
    visible: rows && rows.length > 0
    Layout.fillWidth: true
    spacing: 4
    
    function formatCost(v) {
        if (typeof v !== "number" || isNaN(v)) return "$0";
        return "$" + Math.ceil(v);
    }
    
    function formatTokens(n) {
        if (typeof n !== "number" || isNaN(n)) return "0";
        if (n >= 1_000_000) return parseFloat((n / 1_000_000).toFixed(1)) + "M";
        if (n >= 1_000)     return parseFloat((n / 1_000).toFixed(1)) + "k";
        return String(n);
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Medium
        color: Appearance.colors.colSubtext
        text: rootBlock.title
    }

    Repeater {
        model: rootBlock.rows
        delegate: ColumnLayout {
            id: rowCol
            required property var modelData
            Layout.fillWidth: true
            spacing: 2
            
            property bool isHovered: hoverHandler.hovered
            
            // Subtly highlights the active row on hover
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "transparent"
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
                Layout.alignment: Qt.AlignHCenter
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
