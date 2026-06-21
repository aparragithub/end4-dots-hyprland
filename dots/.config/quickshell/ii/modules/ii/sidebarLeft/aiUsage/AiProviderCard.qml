pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Rectangle {
    id: rootCard
    
    // --- Public Properties ---
    property string title: ""
    property string iconName: "auto_awesome"
    property var service: null
    property color accentColor: Appearance.colors.colPrimary
    
    // States passed from parent/service
    property bool isLoading: false
    property bool isAvailable: false
    property string errorMessage: ""
    property bool bothFail: false
    property string bothFailMessage: ""
    property bool forceContentVisible: false
    
    // Custom content
    default property alias contentData: innerLayout.data
    
    property bool isHovered: hoverArea.containsMouse
    
    Layout.fillWidth: true
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    radius: Appearance.rounding.normal
    
    // Smooth background color change on hover
    color: isHovered ? Qt.lighter(Appearance.colors.colLayer2, 1.03) : Appearance.colors.colLayer2
    
    // Glowing border on hover
    border.color: isHovered ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.3) : "transparent"
    border.width: 1
    
    // Micro-animations
    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    Behavior on color { ColorAnimation { duration: 200 } }
    Behavior on border.color { ColorAnimation { duration: 200 } }
    
    scale: isHovered ? 1.01 : 1.0
    implicitHeight: cardColumn.implicitHeight + 24
    
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        propagateComposedEvents: true
    }
    
    ColumnLayout {
        id: cardColumn
        anchors {
            left: parent.left; right: parent.right
            top: parent.top
            margins: 12
        }
        spacing: 10
        
        // --- Card Header ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            
            MaterialSymbol {
                text: rootCard.iconName
                iconSize: Appearance.font.pixelSize.larger
                color: rootCard.isHovered ? rootCard.accentColor : Appearance.colors.colPrimary
                Behavior on color { ColorAnimation { duration: 200 } }
            }
            
            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
                text: rootCard.title
            }
            
            // Refresh button
            MouseArea {
                id: refreshArea
                implicitWidth: 30
                implicitHeight: 30
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (rootCard.service) rootCard.service.refresh()
                
                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.small
                    color: refreshArea.containsMouse
                        ? Appearance.colors.colLayer3
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                    
                    // Rotation on click
                    RotationAnimation on rotation {
                        running: refreshArea.pressed
                        from: 0; to: 360; duration: 400
                    }
                }
            }
        }
        
        // --- Both-fail state ---
        StyledText {
            visible: rootCard.bothFail
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: rootCard.bothFailMessage
        }
        
        // --- Loading state ---
        StyledText {
            visible: rootCard.isLoading && !rootCard.isAvailable
            Layout.alignment: Qt.AlignHCenter
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("Loading…")
        }
        
        // --- Error state ---
        StyledText {
            visible: !rootCard.isLoading && !rootCard.isAvailable && !rootCard.bothFail && rootCard.errorMessage.length > 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: rootCard.errorMessage
        }
        
        // --- Content Slot ---
        ColumnLayout {
            id: innerLayout
            Layout.fillWidth: true
            spacing: 10
            visible: rootCard.isAvailable || rootCard.forceContentVisible
        }
    }
}
