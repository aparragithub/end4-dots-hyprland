import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root
    property real padding: 4

    // One file per day: ~/.local/state/quickshell/scratchpad/YYYY-MM-DD.txt
    // Directories.state carries a "file://" prefix, so it must be trimmed
    // before being handed to shell commands.
    property string baseDir: FileUtils.trimFileProtocol(`${Directories.state}/scratchpad`)
    property string today: dateStamp()
    property string filePath: `${root.baseDir}/${root.today}.txt`
    property string lastSavedText: ""

    function dateStamp() {
        const d = new Date()
        const y = d.getFullYear()
        const m = String(d.getMonth() + 1).padStart(2, "0")
        const day = String(d.getDate()).padStart(2, "0")
        return `${y}-${m}-${day}`
    }

    function focusActiveItem() {
        textArea.forceActiveFocus()
    }

    onFocusChanged: focus => {
        if (focus) {
            root.checkRollover()
            textArea.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        root.loadToday()
    }

    // Reload today's file into the editor (clears it if the file is absent).
    function loadToday() {
        loadProc.running = false
        loadProc.running = true
    }

    // Persist text to a specific day's file. Empty text means "no note today":
    // the file is removed instead of left as an empty backup.
    function persist(targetPath, text) {
        if (text.length === 0) {
            Quickshell.execDetached(["rm", "-f", targetPath])
            return
        }
        saveProc.targetPath = targetPath
        saveProc.pendingText = text
        saveProc.running = false
        saveProc.running = true
    }

    // Detect a day change while the shell is running: flush the current text to
    // the previous day's file, then start the new day blank.
    function checkRollover() {
        const stamp = root.dateStamp()
        if (stamp === root.today)
            return
        saveTimer.stop()
        root.persist(root.filePath, textArea.text) // filePath still points at the old day
        root.lastSavedText = textArea.text
        root.today = stamp                          // filePath now points at the new day
        root.loadToday()
    }

    Timer {
        id: rolloverTimer
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.checkRollover()
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
                root.persist(root.filePath, currentText)
            }
        }
    }

    Process {
        id: saveProc
        property string targetPath: ""
        property string pendingText: ""
        command: ["bash", "-c", `mkdir -p "$(dirname '${saveProc.targetPath}')" && cat > '${saveProc.targetPath}'`]
        onRunningChanged: {
            if (saveProc.running) {
                saveProc.write(saveProc.pendingText)
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
                text: Translation.tr("Notes") + ` · ${root.today}`
                color: Appearance.colors.colSubtext
            }

            Item { Layout.fillWidth: true }

            RippleButton {
                id: folderButton
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.small

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: Appearance.font.pixelSize.larger
                    text: "folder_open"
                    color: Appearance.colors.colOnLayer1
                }
                onClicked: {
                    Quickshell.execDetached(["bash", "-c", `mkdir -p '${root.baseDir}' && xdg-open '${root.baseDir}'`])
                }
            }

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
                    // A TextArea inside a ScrollView must NOT use anchors.fill:
                    // the ScrollView measures its implicit content height to scroll.
                    // Drive width from the viewport and let height grow with content,
                    // filling the viewport when content is short.
                    width: scrollView.availableWidth
                    height: Math.max(implicitHeight, scrollView.availableHeight)
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
