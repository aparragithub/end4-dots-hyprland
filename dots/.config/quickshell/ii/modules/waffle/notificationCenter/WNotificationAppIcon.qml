import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.waffle.looks

Item {
    id: root

    property string icon: ""
    property real implicitSize: 16
    implicitWidth: implicitSize
    implicitHeight: implicitSize

    IconImage {
        id: iconImage
        anchors.fill: parent
        implicitWidth: root.implicitSize
        implicitHeight: root.implicitSize

        source: root.icon || `${Looks.iconsPath}/apps.svg`
        implicitSize: root.implicitSize
        visible: root.icon !== ""
    }

    ColorOverlay {
        anchors.fill: iconImage
        source: iconImage
        color: Looks.colors.fg
        visible: root.icon === ""
    }
}
