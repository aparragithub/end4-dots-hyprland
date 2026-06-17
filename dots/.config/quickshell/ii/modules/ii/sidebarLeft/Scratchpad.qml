import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root
    property real padding: 4
    property string filePath: `${Directories.state}/scratchpad.txt`
    property string lastSavedText: ""

    function focusActiveItem() {
        textArea.forceActiveFocus()
    }

    onFocusChanged: focus => {
        if (focus) textArea.forceActiveFocus()
    }

    Component.onCompleted: {
        loadProc.running = true
    }

    Process {
        id: loadProc
        command: ["bash", "-c", `[ -f '${root.filePath}' ] && cat '${root.filePath}'`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.lastSavedText = text
                textArea.text = root.lastSavedText
                textArea.cursorPosition = textArea.length
            }
        }
    }

    Timer {
        id: saveTimer
        interval: 500
        repeat: false
        onTriggered: {
            const currentText = textArea.text
            if (currentText !== root.lastSavedText) {
                root.lastSavedText = currentText
                saveProc.running = false
                saveProc.stdinEnabled = true
                saveProc.running = true
            }
        }
    }

    Process {
        id: saveProc
        command: ["bash", "-c", `cat > '${root.filePath}'`]
        onRunningChanged: {
            if (saveProc.running) {
                saveProc.write(root.lastSavedText)
                saveProc.stdinEnabled = false
            }
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            spacing: 4

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                text: Translation.tr("Notes")
                color: Appearance.colors.colSubtext
            }

            Item { Layout.fillWidth: true }

            RippleButton {
                id: keepButton
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.small

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: Appearance.font.pixelSize.larger
                    text: "open_in_new"
                    color: Appearance.colors.colOnLayer1
                }
                onClicked: {
                    if (textArea.length > 0) {
                        Quickshell.clipboardText = textArea.text
                    }
                    Qt.openUrlExternally("https://keep.google.com")
                }
            }

            RippleButton {
                id: clearButton
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.small
                enabled: textArea.length > 0

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: Appearance.font.pixelSize.larger
                    text: "delete"
                    color: clearButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                onClicked: {
                    textArea.text = ""
                    saveTimer.restart()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal - root.padding
            color: Appearance.colors.colLayer2
            clip: true

            ScrollView {
                id: scrollView
                anchors.fill: parent
                anchors.margins: 4
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                StyledTextArea {
                    id: textArea
                    anchors.fill: parent
                    wrapMode: TextArea.Wrap
                    padding: 8
                    placeholderText: Translation.tr("escribe aqui...")
                    color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant

                    background: null

                    cursorDelegate: Rectangle {
                        width: 1
                        color: textArea.activeFocus ? Appearance.colors.colPrimary : "transparent"
                        radius: 1
                    }

                    onTextChanged: saveTimer.restart()
                }
            }
        }
    }
}
