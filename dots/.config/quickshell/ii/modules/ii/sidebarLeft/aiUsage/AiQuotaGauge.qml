pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: rootGauge
    
    // --- Public Properties ---
    property double valuePercent: 0.0 // 0 to 100
    property string title: ""
    property string subtitle: ""
    
    Layout.alignment: Qt.AlignHCenter
    spacing: 4
    
    ClippedFilledCircularProgress {
        id: progress
        Layout.alignment: Qt.AlignHCenter
        implicitSize: 64
        lineWidth: 4
        enableAnimation: true
        value: Math.max(0, Math.min(1, rootGauge.valuePercent / 100))
        
        // Soft gradient color transition based on warning threshold
        colPrimary: rootGauge.valuePercent >= Config.options.sidebar.aiUsage.warningThreshold
            ? Appearance.colors.colError
            : Appearance.colors.colPrimary
            
        accountForLightBleeding: rootGauge.valuePercent < Config.options.sidebar.aiUsage.warningThreshold
        
        Item {
            width: 64; height: 64
            StyledText {
                anchors.centerIn: parent
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
                text: (rootGauge.valuePercent > 0 && rootGauge.valuePercent < 0.5) 
                    ? "<1%" 
                    : Math.round(rootGauge.valuePercent) + "%"
            }
        }
    }
    
    StyledText {
        Layout.alignment: Qt.AlignHCenter
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.Medium
        color: Appearance.colors.colOnLayer1
        text: rootGauge.title
    }
    
    StyledText {
        Layout.alignment: Qt.AlignHCenter
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: rootGauge.subtitle
    }
}
