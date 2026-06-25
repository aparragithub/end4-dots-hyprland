import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

Item {
    id: root
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property int effectiveActiveWorkspaceId: monitor?.activeWorkspace?.id ?? 1
    readonly property int workspacesShown: Config.options.bar.workspaces.shown
    readonly property int workspaceGroup: Math.floor((effectiveActiveWorkspaceId - 1) / workspacesShown)
    readonly property int maxAppIcons: Config.options.bar.workspaces.maxAppIcons
    readonly property bool dynamic: Config.options?.bar.workspaces.dynamic ?? false
    readonly property var sortedWorkspaceIds: {
        const monitorId = root.monitor?.id;
        const ids = HyprlandData.workspaces
            .filter(ws => ws.monitorID === monitorId)
            .map(ws => ws.id)
            .filter(id => id >= 1 && id <= 100);
        ids.sort((a, b) => a - b);
        if (ids.indexOf(root.effectiveActiveWorkspaceId) === -1) {
            ids.push(root.effectiveActiveWorkspaceId);
            ids.sort((a, b) => a - b);
        }
        return ids;
    }
    readonly property int effectiveCount: root.dynamic ? root.sortedWorkspaceIds.length : root.workspacesShown
    function wsValueForIndex(idx) {
        if (root.dynamic) return root.sortedWorkspaceIds[idx];
        return root.workspaceGroup * root.workspacesShown + idx + 1;
    }

    property int pillHeight: 24
    property int iconSize: 16

    // Bump to force re-evaluation of per-pill bindings when windows change.
    property int dataTick: 0
    Connections {
        target: HyprlandData
        function onWindowListChanged() { root.dataTick++ }
    }

    implicitWidth: pillRow.implicitWidth
    implicitHeight: Appearance.sizes.barHeight

    Row {
        id: pillRow
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: root.effectiveCount

            Rectangle {
                id: pill
                required property int index
                readonly property int workspaceValue: root.wsValueForIndex(index)
                readonly property bool isActive: root.effectiveActiveWorkspaceId === workspaceValue
                readonly property var entries: (root.dataTick, HyprlandData.appEntriesForWorkspace(workspaceValue, root.maxAppIcons))
                readonly property bool occupied: (root.dataTick, HyprlandData.hyprlandClientsForWorkspace(workspaceValue).length > 0)
                readonly property color fgColor: isActive ? Appearance.m3colors.m3onPrimary
                    : occupied ? Appearance.m3colors.m3onSecondaryContainer
                    : Appearance.colors.colOnLayer1Inactive

                implicitHeight: root.pillHeight
                implicitWidth: contentRow.implicitWidth + 14
                radius: Appearance.rounding.full
                color: isActive ? Appearance.colors.colPrimary
                    : occupied ? ColorUtils.transparentize(Appearance.m3colors.m3secondaryContainer, 0.4)
                    : "transparent"

                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onPressed: Hyprland.dispatch(`hl.dsp.focus({ workspace = ${pill.workspaceValue}})`)
                }

                Row {
                    id: contentRow
                    anchors.centerIn: parent
                    spacing: 3

                    StyledText { // Workspace number
                        anchors.verticalCenter: contentRow.verticalCenter
                        text: Config.options?.bar.workspaces.numberMap[pill.workspaceValue - 1] || pill.workspaceValue
                        color: pill.fgColor
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Config.options?.bar.workspaces.useNerdFont ? Appearance.font.family.iconNerd : Appearance.font.family.main
                    }

                    Repeater {
                        model: pill.entries.classes

                        Item {
                            id: iconHolder
                            required property var modelData
                            anchors.verticalCenter: contentRow.verticalCenter
                            width: root.iconSize
                            height: root.iconSize

                            IconImage {
                                id: appIcon
                                anchors.fill: parent
                                source: Quickshell.iconPath(AppSearch.guessIcon(iconHolder.modelData), Quickshell.shellPath("assets/icons/fluent/apps.svg"))
                            }

                            Loader {
                                active: Config.options.bar.workspaces.monochromeIcons
                                anchors.fill: appIcon
                                sourceComponent: Item {
                                    Desaturate {
                                        id: desaturatedIcon
                                        visible: false
                                        anchors.fill: parent
                                        source: appIcon
                                        desaturation: 0.8
                                    }
                                    ColorOverlay {
                                        anchors.fill: desaturatedIcon
                                        source: desaturatedIcon
                                        color: ColorUtils.transparentize(pill.fgColor, 0.1)
                                    }
                                }
                            }
                        }
                    }

                    StyledText { // Overflow counter
                        anchors.verticalCenter: contentRow.verticalCenter
                        visible: pill.entries.overflow > 0
                        text: `+${pill.entries.overflow}`
                        color: pill.fgColor
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }
    }
}
