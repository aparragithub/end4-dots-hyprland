pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: rootTable
    
    // --- Public Properties ---
    property string title: Translation.tr("Estimated cost (API rate)")
    
    property double todayCost: -1
    property double weekCost: -1
    property double monthCost: -1
    
    property string todayTokensText: ""
    property string weekTokensText: ""
    property string monthTokensText: ""
    
    Layout.fillWidth: true
    spacing: 6
    
    function formatCost(v) {
        if (typeof v !== "number" || isNaN(v) || v < 0) return "—";
        return "$" + Math.ceil(v);
    }
    
    StyledText {
        Layout.alignment: Qt.AlignHCenter
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.Medium
        color: Appearance.colors.colOnLayer1
        text: rootTable.title
    }
    
    GridLayout {
        Layout.alignment: Qt.AlignHCenter
        columns: 3
        columnSpacing: 16
        rowSpacing: 6 // Increased row spacing for better visual rhythm
        
        // --- Today Row ---
        StyledText {
            visible: rootTable.todayCost >= 0
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: Translation.tr("Today")
        }
        StyledText {
            visible: rootTable.todayCost >= 0
            Layout.alignment: Qt.AlignRight
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: Appearance.colors.colOnLayer1
            text: rootTable.formatCost(rootTable.todayCost)
        }
        StyledText {
            visible: rootTable.todayCost >= 0
            Layout.alignment: Qt.AlignRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: rootTable.todayTokensText
        }
        
        // --- This Week Row ---
        StyledText {
            visible: rootTable.weekCost >= 0
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: Translation.tr("This week")
        }
        StyledText {
            visible: rootTable.weekCost >= 0
            Layout.alignment: Qt.AlignRight
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: Appearance.colors.colOnLayer1
            text: rootTable.formatCost(rootTable.weekCost)
        }
        StyledText {
            visible: rootTable.weekCost >= 0
            Layout.alignment: Qt.AlignRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: rootTable.weekTokensText
        }
        
        // --- This Month Row ---
        StyledText {
            visible: rootTable.monthCost >= 0
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: Translation.tr("This month")
        }
        StyledText {
            visible: rootTable.monthCost >= 0
            Layout.alignment: Qt.AlignRight
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: Appearance.colors.colOnLayer1
            text: rootTable.formatCost(rootTable.monthCost)
        }
        StyledText {
            visible: rootTable.monthCost >= 0
            Layout.alignment: Qt.AlignRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: rootTable.monthTokensText
        }
    }
}
