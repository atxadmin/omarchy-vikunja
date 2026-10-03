import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
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
    contentWidth: Style.space(420)
    contentHeight: Math.min(Style.space(500), popup.availableCardHeight)

    // Project sections remember their folded state by title, so a fold
    // survives the list rebuilding on every collector write.
    property var collapsed: ({})

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
                  onClicked: root.toggleTask(taskCard.modelData.id)
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

        // ------------------------------------------------------------- create
        // The stock PopupCard cannot take keyboard focus (its window type
        // won't accept the layer-shell focus attachment), so an inline
        // TextField would be dead. Instead an "+ Add task" button opens a
        // small focused PanelWindow, the same approach the clipboard
        // plugin's search box uses.
        Rectangle {
          Layout.fillWidth: true
          implicitHeight: addLabel.implicitHeight + Style.space(16)
          radius: Style.space(10)
          color: addRowMouse.containsMouse
            ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.11)
            : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)

          Behavior on color { ColorAnimation { duration: 90 } }

          RowLayout {
            id: addLabel
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(8)

            Text {
              text: "+ Add task"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              Layout.fillWidth: true
              visible: root.state && root.state.projects
              text: "in " + (projectPicker.displayText || "")
              color: root.themeSecondary
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }

          MouseArea {
            id: addRowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              addDialog.open()
              newTaskInput.forceActiveFocus()
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------- add dialog
  // A small centered layer-shell window that CAN take keyboard focus,
  // unlike the popup. Type a title, pick a project, Enter to create.
  PanelWindow {
    id: addDialog

    property bool accepted: false

    visible: false
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-vikunja-add"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    function open() {
      newTaskInput.text = ""
      accepted = false
      visible = true
      newTaskInput.forceActiveFocus()
    }

    function close() {
      visible = false
    }

    MouseArea {
      anchors.fill: parent
      onClicked: addDialog.close()
    }

    Rectangle {
      anchors.centerIn: parent
      width: Style.space(420)
      height: dialogColumn.implicitHeight + Style.space(24)
      radius: Style.space(12)
      color: Color.popups.background

      ColumnLayout {
        id: dialogColumn
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(8)

        Text {
          text: "New task"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        TextField {
          id: newTaskInput
          Layout.fillWidth: true
          placeholderText: "Task title…"
          color: Color.foreground
          placeholderTextColor: root.themeSecondary
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          background: Rectangle {
            implicitWidth: Style.space(320)
            implicitHeight: Style.space(32)
            radius: Style.space(8)
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
            border.width: newTaskInput.activeFocus ? 1 : 0
            border.color: Color.accent
          }
          onAccepted: {
            addDialog.accepted = true
            root.createTask(newTaskInput.text, projectPicker.currentText)
            addDialog.close()
          }
          Keys.onEscapePressed: addDialog.close()
        }

        ComboBox {
          id: projectPicker
          Layout.fillWidth: true
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

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Item { Layout.fillWidth: true }

          Rectangle {
            implicitWidth: cancelText.implicitWidth + Style.space(20)
            implicitHeight: cancelText.implicitHeight + Style.space(10)
            radius: Style.space(8)
            color: cancelMouse.containsMouse
              ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
              : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)

            Text {
              id: cancelText
              anchors.centerIn: parent
              text: "Cancel"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: cancelMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: addDialog.close()
            }
          }

          Rectangle {
            implicitWidth: addText.implicitWidth + Style.space(20)
            implicitHeight: addText.implicitHeight + Style.space(10)
            radius: Style.space(8)
            color: addOkMouse.containsMouse ? Qt.lighter(Color.accent, 1.15) : Color.accent

            Text {
              id: addText
              anchors.centerIn: parent
              text: "Add"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            MouseArea {
              id: addOkMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                addDialog.accepted = true
                root.createTask(newTaskInput.text, projectPicker.currentText)
                addDialog.close()
              }
            }
          }
        }
      }
    }
  }
}