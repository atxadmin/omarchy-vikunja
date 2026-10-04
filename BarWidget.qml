import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar widget + task panel in one entry point, the way the shell expects:
// the widget root extends Ui.Panel (open/close/opened lifecycle + IPC),
// the count label is the bar face, and the task list lives in a
// KeyboardPanel anchored under it. KeyboardPanel (unlike PopupCard) is a
// layer-shell PanelWindow, so the quick-add TextField actually receives
// keystrokes — the same approach derekross/omarchy-tasks uses.
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

  function toggleTask(taskId, markDone) {
    // One collector run does the POST and rewrites the state file, so the
    // FileView watcher fires once with the task already moved.
    var args = ["--toggle", String(taskId)]
    if (markDone) args.push("--done")
    args.push("--write")
    runCollector(args)
  }

  function createTask(title, projectTitle) {
    title = String(title || "").trim()
    if (title === "") return
    var projectId = 0
    if (root.state && root.state.projects)
      for (var i = 0; i < root.state.projects.length; i++)
        if (root.state.projects[i].title === projectTitle) {
          projectId = root.state.projects[i].id
          break
        }
    if (projectId === 0) return
    runCollector(["--create", title, "--project", String(projectId), "--write"])
    newTaskInput.text = ""
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    onFileChanged: stateFile.reload()  // reload() re-reads disk, then onLoaded parses fresh text
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

  KeyboardPanel {
    id: popup

    anchorItem: face
    bar: root.bar
    owner: root
    open: root.opened
    contentWidth: Style.space(420)
    contentHeight: Math.min(Style.space(500), popup.availableCardHeight)
    focusTarget: newTaskInput

    // Project sections remember their folded state by title, so a fold
    // survives the list rebuilding on every collector write.
    property var collapsed: ({})

    PanelKeyCatcher {
      onCloseRequested: popup.close()
    }

    Flickable {
      anchors.fill: parent
      anchors.margins: Style.space(6)
      contentWidth: width
      contentHeight: list.implicitHeight
      clip: true

      ColumnLayout {
        id: list
        width: parent.width
        spacing: Style.space(4)

        // Panel header: title plus the counts that made the bar face
        // change colour, so the top of the card explains itself.
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            text: "Vikunja Tasks"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            Layout.fillWidth: true
            text: root.state
              ? (root.state.total + " open")
              : ""
            color: root.themeSecondary
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Text {
            visible: root.state && root.state.overdue > 0
            text: root.state ? (root.state.overdue + " overdue") : ""
            color: Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            visible: root.state && root.state.due_today > 0
            text: root.state ? (root.state.due_today + " today") : ""
            color: root.themeWarning
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Rectangle {
            Layout.preferredWidth: Style.space(10)
            Layout.preferredHeight: Style.space(10)
            radius: height / 2
            color: "transparent"
            border.width: 1
            border.color: root.themeOutline

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.refresh()
            }
          }
        }

        // Quick-add line, the omarchy-tasks pattern: type a title, pick
        // a project, press Enter. Works because KeyboardPanel is a
        // layer-shell window that takes real keyboard focus.
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          TextField {
            id: newTaskInput
            Layout.fillWidth: true
            placeholderText: "Add a task…"
            color: Color.foreground
            placeholderTextColor: root.themeSecondary
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            background: Rectangle {
              implicitHeight: Style.space(32)
              radius: Style.space(8)
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
              border.width: newTaskInput.activeFocus ? 1 : 0
              border.color: Color.accent
            }
            onAccepted: root.createTask(newTaskInput.text, projectPicker.currentText)
          }

          ComboBox {
            id: projectPicker
            Layout.preferredWidth: Style.space(130)
            model: {
              var names = []
              if (root.state && root.state.projects)
                for (var i = 0; i < root.state.projects.length; i++)
                  names.push(root.state.projects[i].title)
              return names
            }
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        Rectangle {
          Layout.fillWidth: true
          height: 1
          color: root.themeOutline
          opacity: 0.5
        }

        Repeater {
          model: root.state && root.state.projects ? root.state.projects : []

          ColumnLayout {
            required property var modelData
            id: projectColumn
            Layout.fillWidth: true
            spacing: Style.space(4)

            readonly property bool collapsed: popup.collapsed[modelData.title] === true

            // Section header: title, count, and a fold arrow, the whole
            // row clickable to toggle the section.
            Rectangle {
              Layout.fillWidth: true
              implicitHeight: headerRow.implicitHeight + Style.space(8)
              radius: Style.space(8)
              color: headerMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10)
                   : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)

              RowLayout {
                id: headerRow
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(8)

                Text {
                  text: projectColumn.modelData.title
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }

                Text {
                  Layout.fillWidth: true
                  text: "(" + projectColumn.modelData.tasks.length + ")"
                  color: root.themeSecondary
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                Text {
                  text: projectColumn.collapsed ? "▸" : "▾"
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }

              MouseArea {
                id: headerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  var next = {}
                  for (var key in popup.collapsed) next[key] = popup.collapsed[key]
                  if (next[projectColumn.modelData.title]) delete next[projectColumn.modelData.title]
                  else next[projectColumn.modelData.title] = true
                  popup.collapsed = next
                }
              }
            }

            Repeater {
              model: projectColumn.modelData.tasks

              // One task per card, the shape the notification plugin uses:
              // a raised rounded rect of foreground at low opacity, with a
              // hover tint, so a run of tasks reads as a pile of things
              // rather than a spreadsheet.
              Rectangle {
                required property var modelData
                id: taskCard
                Layout.fillWidth: true
                visible: !projectColumn.collapsed
                Layout.preferredHeight: cardContent.implicitHeight + Style.space(16)
                radius: Style.space(10)
                color: cardMouse.containsMouse
                  ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.11)
                  : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)

                Behavior on color { ColorAnimation { duration: 90 } }

                // Whole card toggles the task; the checkbox is the visual,
                // not the only target. A 14px box is a hard target to hit.
                MouseArea {
                  id: cardMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleTask(taskCard.modelData.id, true)
                }

                RowLayout {
                  id: cardContent
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  spacing: Style.space(10)

                  Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: Style.space(14)
                    Layout.preferredHeight: Style.space(14)
                    radius: Style.space(3)
                    color: "transparent"
                    border.width: 1
                    border.color: taskCard.modelData.due && taskCard.modelData.due.overdue
                      ? Color.urgent
                      : taskCard.modelData.due && taskCard.modelData.due.today
                        ? root.themeWarning
                        : root.themeOutline
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(1)

                    Text {
                      Layout.fillWidth: true
                      text: taskCard.modelData.title
                      textFormat: Text.PlainText
                      color: Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.subtitle
                      wrapMode: Text.WordWrap
                    }

                    Text {
                      Layout.fillWidth: true
                      visible: taskCard.modelData.due !== null
                      text: taskCard.modelData.due
                        ? "Due " + Qt.formatDate(taskCard.modelData.due.date, "d MMM") : ""
                      color: taskCard.modelData.due && taskCard.modelData.due.overdue
                        ? Color.urgent
                        : taskCard.modelData.due && taskCard.modelData.due.today
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
        // Completed section: every task checked off lands here, newest
        // first, so an accidental click is always visible and recoverable
        // by clicking the card again (which un-completes it).
        Rectangle {
          Layout.fillWidth: true
          visible: root.state && root.state.completed && root.state.completed.length > 0
          implicitHeight: completedHeaderRow.implicitHeight + Style.space(8)
          radius: Style.space(8)
          color: completedHeaderMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10)
               : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)

          RowLayout {
            id: completedHeaderRow
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            Text {
              text: "Completed"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              Layout.fillWidth: true
              text: root.state && root.state.completed
                ? "(" + root.state.completed.length + ")" : ""
              color: root.themeSecondary
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              text: popup.collapsed["Completed"] ? "▸" : "▾"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }

          MouseArea {
            id: completedHeaderMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var next = {}
              for (var key in popup.collapsed) next[key] = popup.collapsed[key]
              if (next["Completed"]) delete next["Completed"]
              else next["Completed"] = true
              popup.collapsed = next
            }
          }
        }

        Repeater {
          model: root.state && root.state.completed ? root.state.completed : []

          Rectangle {
            required property var modelData
            id: doneCard
            Layout.fillWidth: true
            visible: popup.collapsed["Completed"] !== true
            Layout.preferredHeight: doneRow.implicitHeight + Style.space(16)
            radius: Style.space(10)
            color: doneMouse.containsMouse
              ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.11)
              : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)

            Behavior on color { ColorAnimation { duration: 90 } }

            // Click a completed card to un-complete it (accidental-click
            // recovery without leaving the panel).
            MouseArea {
              id: doneMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleTask(doneCard.modelData.id, false)
            }

            RowLayout {
              id: doneRow
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(10)

              Text {
                Layout.alignment: Qt.AlignVCenter
                text: "✓"
                color: Color.accent
                font.pixelSize: Style.font.body
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(1)

                Text {
                  Layout.fillWidth: true
                  text: doneCard.modelData.title
                  textFormat: Text.PlainText
                  color: root.themeSecondary
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.strikeout: true
                  wrapMode: Text.WordWrap
                }

                Text {
                  Layout.fillWidth: true
                  visible: doneCard.modelData.project !== ""
                  text: doneCard.modelData.project
                  color: root.themeSecondary
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