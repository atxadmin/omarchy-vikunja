import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar widget + task panel in one entry point, the way the shell expects:
// the widget root extends Ui.Panel (open/close/opened lifecycle + IPC),
// the count label is the bar face, and the task list lives in a PopupCard
// anchored under it.
Panel {
  id: root

  moduleName: "com.burtoncommand.vikunja"
  ipcTarget: "com.burtoncommand.vikunja"

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") || "") + "/.local/state"
  readonly property string statePath: stateHome + "/omarchy/plugins/vikunja/tasks.json"
  readonly property string pluginDir: (Quickshell.env("HOME") || "")
    + "/.config/omarchy/plugins/com.burtoncommand.vikunja"

  property var state: null

  // Catppuccin accents; Color.qml only guarantees foreground/accent/urgent.
  readonly property color themeWarning: "#fab387"
  readonly property color themeSecondary: "#6c7086"
  readonly property color themeOutline: "#585b70"

  function reload() {
    try {
      state = JSON.parse(stateFile.text())
    } catch (e) {
      state = null
    }
  }

  function runCollector(args) {
    Quickshell.execDetached(["python3", pluginDir + "/collect.py"].concat(args))
  }

  function refresh() {
    runCollector(["--write"])
  }

  function toggleTask(taskId) {
    runCollector(["--toggle", String(taskId), "--done"])
    // The collector rewrites the state file; the FileView watcher picks it
    // up and both the label and the list rebind. Refresh right after so
    // counts settle even if the write races the toggle.
    Quickshell.execDetached(["bash", "-c",
      "sleep 1; python3 '" + pluginDir + "/collect.py' --write"])
  }

  FileView {
    id: stateFile
    path: root.statePath
    onFileChanged: root.reload()
    onLoaded: root.reload()
  }

  Component.onCompleted: root.reload()

  // ------------------------------------------------------------------- face

  implicitWidth: face.implicitWidth
  implicitHeight: face.implicitHeight

  Item {
    id: face
    implicitWidth: label.implicitWidth + Style.space(8)
    implicitHeight: Math.max(label.implicitHeight, Style.bar.iconSlot)

    MouseArea {
      id: faceMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        root.refresh()
        root.toggle()
      }
    }

    Text {
      id: label
      anchors.centerIn: parent
      text: root.state ? String(root.state.total) : "…"
      color: root.state && root.state.overdue > 0 ? Color.urgent
           : root.state && root.state.due_today > 0 ? root.themeWarning
           : root.barForeground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Rectangle {
      visible: root.state && root.state.overdue > 0
      anchors.right: face.right
      anchors.rightMargin: Style.space(1)
      anchors.top: face.top
      anchors.topMargin: Style.space(3)
      width: Style.space(4)
      height: width
      radius: width / 2
      color: Color.urgent
    }
  }

  // ------------------------------------------------------------------ panel

  PopupCard {
    id: popup

    anchorItem: face
    bar: root.bar
    owner: root
    open: root.opened
    contentWidth: Style.space(300)
    contentHeight: Math.min(Style.space(400), popup.availableCardHeight)

    Flickable {
      anchors.fill: parent
      anchors.margins: Style.space(4)
      contentWidth: width
      contentHeight: list.implicitHeight
      clip: true

      ColumnLayout {
        id: list
        width: parent.width

        Repeater {
          model: root.state && root.state.projects ? root.state.projects : []

          ColumnLayout {
            required property var modelData
            id: projectColumn
            Layout.fillWidth: true
            spacing: Style.space(2)

            Text {
              Layout.fillWidth: true
              text: "%1 (%2)".arg(projectColumn.modelData.title)
                                   .arg(projectColumn.modelData.tasks.length)
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Repeater {
              model: projectColumn.modelData.tasks

              RowLayout {
                required property var modelData
                id: taskRow
                Layout.fillWidth: true
                spacing: Style.space(3)

                Rectangle {
                  Layout.preferredWidth: Style.space(10)
                  Layout.preferredHeight: Style.space(10)
                  radius: Style.space(2)
                  color: "transparent"
                  border.width: 1
                  border.color: taskRow.modelData.due && taskRow.modelData.due.overdue
                    ? Color.urgent
                    : taskRow.modelData.due && taskRow.modelData.due.today
                      ? root.themeWarning
                      : root.themeOutline

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleTask(taskRow.modelData.id)
                  }
                }

                Text {
                  id: taskLabel
                  Layout.fillWidth: true
                  text: taskRow.modelData.title
                  color: root.barForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  wrapMode: Text.WordWrap
                }

                Text {
                  visible: taskRow.modelData.due !== null
                  text: taskRow.modelData.due
                    ? Qt.formatDate(taskRow.modelData.due.date, "d MMM") : ""
                  color: taskRow.modelData.due && taskRow.modelData.due.overdue
                    ? Color.urgent
                    : taskRow.modelData.due && taskRow.modelData.due.today
                      ? root.themeWarning
                      : root.themeSecondary
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }
            }
          }
        }
      }
    }
  }
}