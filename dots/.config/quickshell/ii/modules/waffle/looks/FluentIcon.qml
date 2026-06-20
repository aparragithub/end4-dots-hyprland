import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell.Widgets
import qs.modules.common
import qs.modules.waffle.looks

Item {
    id: root
    required property string icon
    property string source: ""
    property bool filled: false
    property bool animated: true
    property bool monochrome: true
    property color color: Looks.colors.fg
    // Should be 16, but it appears the icons have some padding, 
    // Unlike the Windows-only Segoe UI icons, the open source FluentUI ones are hella small
    property int implicitSize: 20
    implicitWidth: implicitSize
    implicitHeight: implicitSize

    IconImage {
        id: iconImage
        anchors.fill: parent
        source: root.source !== "" ? root.source : root.icon === "" ? "" : `${Looks.iconsPath}/${root.icon}${filled ? "-filled" : ""}.svg`
        implicitSize: root.implicitSize
        visible: !root.monochrome
    }

    ColorOverlay {
        anchors.fill: iconImage
        source: iconImage
        color: root.color
        visible: root.monochrome
    }
}
