import QtQuick
import Quickshell
import Quickshell.Io

// Service-kind plugin: periodically runs collect.py to refresh
// ~/.local/state/omarchy/plugins/vikunja/tasks.json, which the bar
// widget and panel read. Modeled on the Ollama Cloud usage plugin.
Item {
  id: root

  property var manifest: null
  property var shell: null

  readonly property string pluginDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  readonly property string collector: pluginDir + "/collect.py"
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") || "") + "/.local/state"
  readonly property string statePath: stateHome + "/omarchy/plugins/vikunja/tasks.json"

  function collect(force) {
    if (pluginDir === "" || collectProcess.running) return
    var flags = force === true ? " --write --force" : " --write"
    var inner = "python3 " + collector + flags + " 2>&1 | head -c 2048"
    collectProcess.command = ["timeout", "-k", "2", "30", "bash", "-c", "set -o pipefail; " + inner]
    collectProcess.running = true
  }

  // Tasks change when the user adds one elsewhere; 5 minutes is fine,
  // and the panel forces a refresh on open anyway.
  Timer {
    interval: 300000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.collect(false)
  }

  // Refresh whenever the record changes (toggle from the panel, or a
  // manual run) so widgets listening to the file pick it up instantly.
  FileView {
    path: root.statePath
  }

  Process {
    id: collectProcess
    stdout: SplitParser {
      onRead: line => {
        if (String(line).startsWith("ERROR"))
          console.warn("vikunja:", line)
      }
    }
  }
}