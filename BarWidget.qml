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
// KeyboardPanel anchored under it.
//
// Panel layout (approved mockup sketches/001-compact-pills):
// header -> quick-add with list picker (defaults to Daniel) ->
// All/Today/Overdue filter pills -> project pills with counts, Daniel
// first -> flat task list -> Completed (folded, click to recover).
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

  // Panel filters: "all" | "today" | "overdue". Project pill filter is a
  // title, "" means show every list.
  property string filter: "all"
  property string activeProject: ""

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

  function createTask(title, projectTitle, dueChoice) {
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
    var args = ["--create", title, "--project", String(projectId)]
    if (dueChoice && dueChoice.key !== "none") {
      var d = new Date()
      d.setDate(d.getDate() + dueChoice.days)
      args = args.concat(["--due", Qt.formatDate(d, "yyyy-MM-dd")])
    }
    args.push("--write")
    runCollector(args)
    newTaskInput.text = ""
  }

  // Quick-add due-date choices; the ISO date is computed at submit time.
  readonly property var dueChoices: [
    { key: "none", label: "No date", days: -1 },
    { key: "today", label: "Today", days: 0 },
    { key: "tomorrow", label: "Tomorrow", days: 1 },
    { key: "week", label: "Next week", days: 7 }
  ]

  // Projects with Daniel pinned first; everything else keeps collector order.
  function sortedProjects() {
    if (!root.state || !root.state.projects) return []
    var list = root.state.projects.slice()
    list.sort(function(a, b) {
      if (a.title === "Daniel") return -1
      if (b.title === "Daniel") return 1
      return 0
    })
    return list
  }

  // Flat list of open tasks, filtered by the pill row and project pills.
  function openTasks() {
    var rows = []
    if (!root.state || !root.state.projects) return rows
    for (var p = 0; p < root.state.projects.length; p++) {
      var proj = root.state.projects[p]
      if (root.activeProject !== "" && proj.title !== root.activeProject) continue
      for (var t = 0; t < proj.tasks.length; t++) {
        var task = proj.tasks[t]
        if (root.filter === "today" && !task.due_today) continue
        if (root.filter === "overdue" && !task.overdue) continue
        rows.push({
          id: task.id,
          title: task.title,
          due: task.due,
          overdue: task.overdue,
          due_today: task.due_today,
          project: proj.title
        })
      }
    }
    return rows
  }

  function setDue(taskId, days) {
    // Positive days sets a date N days out; null clears the due date.
    if (days === null) {
      runCollector(["--set-due", String(taskId), "--write"])
      return
    }
    var d = new Date()
    d.setDate(d.getDate() + days)
    var iso = Qt.formatDate(d, "yyyy-MM-dd")
    runCollector(["--set-due", String(taskId), "--due", iso, "--write"])
  }

  function dueLabel(task) {
    if (!task.due) return ""
    if (task.overdue) return "Overdue"
    if (task.due_today) return "Today"
    return "Due " + Qt.formatDate(new Date(task.due), "d MMM")
  }

  function dueColor(task) {
    if (!task.due) return root.themeSecondary
    if (task.overdue) return Color.urgent
    if (task.due_today) return root.themeWarning
    return root.themeSecondary
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
    contentHeight: Math.min(Style.space(560), popup.availableCardHeight)
    focusTarget: newTaskInput

    property bool completedCollapsed: true

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
        spacing: Style.space(6)

        // Header: title, colour-coded summary, refresh and close.
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
              ? (root.state.overdue > 0 || root.state.due_today > 0
                   ? (root.state.overdue > 0 ? root.state.overdue + " overdue" : "")
                     + (root.state.overdue > 0 && root.state.due_today > 0 ? " · " : "")
                     + (root.state.due_today > 0 ? root.state.due_today + " today" : "")
                   : root.state.total + " open")
              : ""
            color: root.state && root.state.overdue > 0 ? Color.urgent
                 : root.state && root.state.due_today > 0 ? root.themeWarning
                 : root.themeSecondary
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Rectangle {
            Layout.preferredWidth: Style.space(24)
            Layout.preferredHeight: Style.space(24)
            radius: height / 2
            color: refreshMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12) : "transparent"
            Text {
              anchors.centerIn: parent
              text: "⟳"
              color: root.themeSecondary
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            MouseArea {
              id: refreshMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.refresh()
            }
          }

          Rectangle {
            Layout.preferredWidth: Style.space(24)
            Layout.preferredHeight: Style.space(24)
            radius: height / 2
            color: closeMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12) : "transparent"
            Text {
              anchors.centerIn: parent
              text: "✕"
              color: root.themeSecondary
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: popup.close()
            }
          }
        }

        // Quick-add: type a title, pick the destination list, press Enter
        // or hit Add. Defaults to the Daniel list whenever state loads.
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

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
            onAccepted: root.createTask(newTaskInput.text, projectPicker.currentText, root.dueChoices[duePicker.currentIndex])
          }

          ComboBox {
            id: duePicker
            Layout.preferredWidth: Style.space(110)
            model: {
              var labels = []
              for (var i = 0; i < root.dueChoices.length; i++)
                labels.push(root.dueChoices[i].label)
              return labels
            }
            currentIndex: 0
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          ComboBox {
            id: projectPicker
            Layout.preferredWidth: Style.space(120)
            model: {
              var names = []
              var projects = root.sortedProjects()
              for (var i = 0; i < projects.length; i++)
                names.push(projects[i].title)
              return names
            }
            // Default to the Daniel list on every state rebuild.
            onModelChanged: {
              currentIndex = Math.max(0, find("Daniel"))
            }
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Rectangle {
            Layout.preferredWidth: addBtnLabel.implicitWidth + Style.space(16)
            Layout.preferredHeight: Style.space(32)
            radius: Style.space(8)
            color: addBtnMouse.containsMouse ? Qt.lighter(Color.accent, 1.15) : Color.accent
            Behavior on color { ColorAnimation { duration: 90 } }

            Text {
              id: addBtnLabel
              anchors.centerIn: parent
              text: "Add"
              color: Color.background
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            MouseArea {
              id: addBtnMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.createTask(newTaskInput.text, projectPicker.currentText, root.dueChoices[duePicker.currentIndex])
            }
          }
        }

        // Filter pills: All / Today / Overdue.
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          Repeater {
            model: [
              { key: "all", label: "All" },
              { key: "today", label: "Today" },
              { key: "overdue", label: "Overdue" }
            ]

            Rectangle {
              required property var modelData
              Layout.fillWidth: true
              implicitHeight: Style.space(28)
              radius: height / 2
              color: root.filter === modelData.key ? Color.accent
                   : filterMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
                   : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)
              Behavior on color { ColorAnimation { duration: 90 } }

              Text {
                anchors.centerIn: parent
                text: modelData.label
                color: root.filter === modelData.key ? Color.background : Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: root.filter === modelData.key
              }

              MouseArea {
                id: filterMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.filter = modelData.key
              }
            }
          }
        }

        // Project pills with live counts, Daniel first. Click to filter
        // the list below to that project; click again to clear.
        Flow {
          Layout.fillWidth: true
          spacing: Style.space(6)

          Repeater {
            model: root.sortedProjects()

            Rectangle {
              required property var modelData
              width: projPillLabel.implicitWidth + Style.space(20)
              height: Style.space(26)
              radius: height / 2
              color: root.activeProject === modelData.title ? Color.accent
                   : projPillMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
                   : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10)
              Behavior on color { ColorAnimation { duration: 90 } }

              Text {
                id: projPillLabel
                anchors.centerIn: parent
                text: modelData.title + "  " + modelData.tasks.length
                color: root.activeProject === modelData.title ? Color.background : Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: root.activeProject === modelData.title
              }

              MouseArea {
                id: projPillMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.activeProject = root.activeProject === modelData.title ? "" : modelData.title
                }
              }
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          height: 1
          color: root.themeOutline
          opacity: 0.5
        }

        // Flat task list, filtered by the pills above. Whole card toggles
        // the task; the checkbox is the visual, not the only target.
        Repeater {
          model: root.openTasks()

          Rectangle {
            required property var modelData
            id: taskCard
            Layout.fillWidth: true
            Layout.preferredHeight: cardRow.implicitHeight + Style.space(12)
            radius: Style.space(10)
            color: cardMouse.containsMouse
              ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.11)
              : "transparent"
            Behavior on color { ColorAnimation { duration: 90 } }

            MouseArea {
              id: cardMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleTask(taskCard.modelData.id, true)
            }

            RowLayout {
              id: cardRow
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(10)

              Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Style.space(14)
                Layout.preferredHeight: Style.space(14)
                radius: Style.space(3)
                color: "transparent"
                border.width: 1
                border.color: taskCard.modelData.overdue
                  ? Color.urgent
                  : taskCard.modelData.due_today
                    ? root.themeWarning
                    : root.themeOutline
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                  Layout.fillWidth: true
                  text: taskCard.modelData.title
                  textFormat: Text.PlainText
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  elide: Text.ElideRight
                }

                Text {
                  Layout.fillWidth: true
                  visible: root.activeProject === "" && taskCard.modelData.project !== ""
                  text: taskCard.modelData.project
                  color: root.themeSecondary
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }

              Text {
                Layout.alignment: Qt.AlignVCenter
                visible: taskCard.modelData.due !== null
                text: root.dueLabel(taskCard.modelData)
                color: root.dueColor(taskCard.modelData)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }

            // Due-date quick buttons, shown only on hover so the list
            // stays clean. Must sit above the card's MouseArea to win
            // clicks; the card itself still toggles on the rest of it.
            Row {
              id: dueRow
              visible: cardMouse.containsMouse
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(4)
              spacing: Style.space(4)

              Repeater {
                model: [
                  { label: "T", days: 0 },
                  { label: "T+1", days: 1 },
                  { label: "+1w", days: 7 },
                  { label: "✕", days: null }
                ]

                Rectangle {
                  required property var modelData
                  width: dueBtnLabel.implicitWidth + Style.space(8)
                  height: Style.space(20)
                  radius: height / 2
                  color: dueBtnMouse.containsMouse
                    ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.25)
                    : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.14)

                  Text {
                    id: dueBtnLabel
                    anchors.centerIn: parent
                    text: modelData.label
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: dueBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setDue(taskCard.modelData.id, modelData.days)
                  }
                }
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.openTasks().length === 0
          text: "Nothing here"
          color: root.themeSecondary
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
        }

        // Completed section: every task checked off lands here. Folded by
        // default so the panel stays focused on open work; click a card
        // to un-complete (accidental-click recovery).
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
              text: popup.completedCollapsed ? "▸" : "▾"
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
            onClicked: popup.completedCollapsed = !popup.completedCollapsed
          }
        }

        Repeater {
          model: popup.completedCollapsed
            ? []
            : (root.state && root.state.completed ? root.state.completed : [])

          Rectangle {
            required property var modelData
            id: doneCard
            Layout.fillWidth: true
            Layout.preferredHeight: doneRow.implicitHeight + Style.space(12)
            radius: Style.space(10)
            color: doneMouse.containsMouse
              ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.11)
              : "transparent"

            Behavior on color { ColorAnimation { duration: 90 } }

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
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(10)

              Text {
                Layout.alignment: Qt.AlignVCenter
                text: "✓"
                color: Color.accent
                font.pixelSize: Style.font.body
              }

              Text {
                Layout.fillWidth: true
                text: doneCard.modelData.title
                textFormat: Text.PlainText
                color: root.themeSecondary
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                font.strikeout: true
                elide: Text.ElideRight
              }

              Text {
                Layout.alignment: Qt.AlignVCenter
                visible: doneCard.modelData.project !== ""
                text: doneCard.modelData.project
                color: root.themeSecondary
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.state && root.state.updated !== undefined
          text: root.state && root.state.updated !== undefined
            ? "Saved · " + root.state.updated : ""
          color: root.themeOutline
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }
    }
  }
}