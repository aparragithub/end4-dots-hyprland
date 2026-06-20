import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common

Item {
    id: root
    required property string iconName
    property bool separateLightDark: false
    property bool tryCustomIcon: true
    property bool animated: true
    property bool isMask: true
    property string fallback: `${Looks.iconsPath}/apps.svg`
    
    property real implicitSize: 26
    implicitWidth: implicitSize
    implicitHeight: implicitSize

    readonly property string iconSource: tryCustomIcon ? `${Looks.iconsPath}/${root.iconName}${!root.separateLightDark ? "" : Looks.dark ? "-dark" : "-light"}.svg` : fallback

    IconImage {
        id: iconImage
        anchors.fill: parent
        source: root.iconSource
        implicitSize: root.implicitSize
        visible: !root.isMask
    }

    ColorOverlay {
        anchors.fill: iconImage
        source: iconImage
        color: Looks.colors.fg
        visible: root.isMask
    }
}
