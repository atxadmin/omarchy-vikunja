import QtQuick
import Quickshell
import Quickshell.Io

// Bar widget: shows the open-task count, red when anything is overdue.
Item {
  id: root

  property var manifest: null
  property var shell: null

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") || "") + "/.local/state"
  readonly property string statePath: stateHome + "/omarchy/plugins/vikunja/tasks.json"

  property var state: null

  implicitWidth: label.implicitWidth + 16
  implicitHeight: label.implicitHeight + 8

  FileView {
    id: stateFile
    path: root.statePath
    onFileChanged: root.reload()
    onLoaded: root.reload()
  }

  function reload() {
    try {
      root.state = JSON.parse(stateFile.text())
    } catch (e) {
      root.state = null
    }
  }

  // Click opens the panel (wired by the shell's panel loader).
  MouseArea {
    anchors.fill: parent
    onClicked: root.openPanel()
  }

  function openPanel() {
    if (typeof shell !== "undefined" && shell && shell.vikunjaPanel) {
      shell.vikunjaPanel.open()
      root.forceCollect()
    }
  }

  function forceCollect() {
    // Trigger the service's collector via the shared record: the service
    // kind watches for a touch file as a "refresh now" signal.
    Quickshell.execDetached(["bash", "-c",
      "touch " + stateHome + "/omarchy/plugins/vikunja/refresh"])
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: root.state ? "" + root.state.total : "…"
    color: root.state && root.state.overdue > 0 ? "#f38ba8"
         : root.state && root.state.due_today > 0 ? "#fab387"
         : palette.text
    font.family: Quickshell.env("OMARCHY_FONT_FAMILY") || "monospace"
    font.pointSize: 11
  }

  Rectangle {
    width: 4; height: 4; radius: 2
    anchors.top: parent.top
    anchors.topMargin: 3
    anchors.horizontalCenter: parent.horizontalCenter
    color: root.state && root.state.overdue > 0 ? "#f38ba8" : "transparent"
    visible: root.state && root.state.overdue > 0
  }
}