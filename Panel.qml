import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Panel: floating window listing open tasks grouped by project.
// Click a task to toggle it done (confirm first for pending->done);
// the record refreshes and the list reloads via FileView.
PanelWindow {
  id: root

  property var manifest: null
  property var shell: null

  readonly property string pluginDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") || "") + "/.local/state"
  readonly property string statePath: stateHome + "/omarchy/plugins/vikunja/tasks.json"

  property var state: null
  property int toggleTarget: -1

  anchors { top: true; right: true }
  margins { top: 60; right: 12 }
  implicitWidth: 380
  implicitHeight: 520
  color: "transparent"
  visible: false

  function reload() {
    try { root.state = JSON.parse(stateFile.text()) }
    catch (e) { root.state = null }
  }

  function toggle(taskId, markDone) {
    // The caller passes the target state from the cached panel data;
    // scoped API tokens cannot re-GET a single task.
    Quickshell.execDetached(["timeout", "-k", "2", "30", "python3",
      pluginDir + "/collect.py", "--toggle", "" + taskId].concat(
        markDone ? ["--done"] : []))
  }

  FileView {
    id: stateFile
    path: root.statePath
    onFileChanged: root.reload()
    onLoaded: root.reload()
    watchChanges: true
  }

  function open() {
    // Force a fresh fetch, then show.
    Quickshell.execDetached(["bash", "-c",
      "touch " + root.stateHome + "/omarchy/plugins/vikunja/refresh"])
    root.visible = true
    root.reload()
  }

  Rectangle {
    anchors.fill: parent
    radius: 12
    color: "#1e1e2e"
    border.color: "#45475a"
    border.width: 1

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 12
      spacing: 8

      RowLayout {
        Layout.fillWidth: true
        Text {
          text: root.state ? "Vikunja — %1 open".arg(root.state.total) : "Vikunja"
          color: "#cdd6f4"
          font.pointSize: 13
          font.bold: true
        }
        Item { Layout.fillWidth: true }
        Text {
          text: root.state && root.state.overdue > 0 ? "%1 overdue".arg(root.state.overdue) : ""
          color: "#f38ba8"
          font.pointSize: 10
          visible: root.state && root.state.overdue > 0
        }
        Text {
          text: "✕"
          color: "#6c7086"
          font.pointSize: 12
          MouseArea { anchors.fill: parent; onClicked: root.visible = false }
        }
      }

      ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ListView {
          id: list
          model: root.state ? root.state.projects : []
          spacing: 4

          delegate: ColumnLayout {
            id: proj
            required property var modelData
            width: list.width
            spacing: 2

            Text {
              text: "%1 (%2)".arg(proj.modelData.title).arg(proj.modelData.tasks.length)
              color: "#89b4fa"
              font.pointSize: 11
              font.bold: true
            }

            Repeater {
              model: proj.modelData.tasks

              RowLayout {
                id: task
                required property var modelData
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                  width: 12; height: 12; radius: 3
                  y: 2
                  color: "#313244"
                  border.color: task.modelData.overdue ? "#f38ba8"
                               : task.modelData.due_today ? "#fab387" : "#585b70"
                }
                Text {
                  Layout.fillWidth: true
                  text: task.modelData.title
                  color: "#cdd6f4"
                  font.pointSize: 10
                  wrapMode: Text.Wrap
                }
                Text {
                  visible: !!task.modelData.due
                  text: {
                    var d = new Date(task.modelData.due)
                    return d.toLocaleDateString(Qt.locale(), "M/d")
                  }
                  color: task.modelData.overdue ? "#f38ba8"
                         : task.modelData.due_today ? "#fab387" : "#6c7086"
                  font.pointSize: 9
                }
                MouseArea {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (confirm("Mark '%1' as done?".arg(task.modelData.title)))
                      root.toggle(task.modelData.id, true)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}