pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.zhouzhuojie.oconfig"
  ipcTarget: "io.github.zhouzhuojie.oconfig"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var settings: ({})
  readonly property var barIdentity: hostWidget || root

  readonly property string pluginDir: Model.fileUrlToPath(Qt.resolvedUrl("."))
  readonly property string cli: pluginDir + "/bin/oconfig"

  property var status: Model.emptyStatus()
  property string lastAction: ""
  property bool editingRemote: false
  readonly property string barLabel: {
    if (!status.initialized) return "󰆓"
    if (status.untracked > 0) return "󰆓 " + status.untracked
    return "󰆓"
  }
  readonly property string barTooltip: Model.summaryLine(status)
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontFam: bar ? bar.fontFamily : Style.font.family

  function open() {
    root.refresh()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
      if (keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    if (root.editingRemote) root.cancelEditingRemote()
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    statusProc.running = false
    statusProc.running = true
  }

  function setting(key, fallback) {
    if (root.settings && root.settings[key] !== undefined && String(root.settings[key]) !== "")
      return String(root.settings[key])
    return fallback
  }

  function runCli(args) {
    actionProc.command = [root.cli].concat(args)
    actionProc.running = true
  }

  function pushStore() {
    var r = setting("remote", "")
    if (r !== "") root.runCli(["push", "--remote", r])
    else root.runCli(["push"])
  }

  function pullStore() {
    var r = setting("remote", "")
    if (r !== "") root.runCli(["pull", "--remote", r])
    else root.runCli(["pull"])
  }

  function persistRemoteSetting(url) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function")
      return
    var entry = { id: root.moduleName }
    for (var key in root.settings)
      if (key !== "id") entry[key] = root.settings[key]
    entry.remote = url
    root.bar.shell.updateEntryInline(root.moduleName, entry)
    root.settings = entry
  }

  function startEditingRemote() {
    root.editingRemote = true
    Qt.callLater(function() {
      if (!remoteField) return
      var current = root.status.remote || setting("remote", "")
      remoteField.text = current
      if (current === "") pasteProc.running = true
      remoteField.selectAll()
      remoteField.forceActiveFocus()
    })
  }

  function cancelEditingRemote() {
    root.editingRemote = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function commitRemote() {
    var url = String(remoteField.text || "").trim()
    root.editingRemote = false
    if (url === "") {
      root.lastAction = "remote cleared — store stays local"
      persistRemoteSetting("")
      Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
      return
    }
    persistRemoteSetting(url)
    if (root.status.initialized)
      root.runCli(["remote", url])
    else
      root.lastAction = "remote saved — press i to init (clones if the URL has history)"
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  Process {
    id: statusProc
    command: [root.cli, "--json", "status"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.status = Model.parseStatus(text)
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {
      id: actionOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: actionErr
      waitForEnd: true
    }
    onExited: function() {
      var out = String(actionOut.text || "").trim()
      var err = String(actionErr.text || "").trim()
      root.lastAction = err !== "" ? (out !== "" ? out + "\n" + err : err) : out
      root.refresh()
    }
  }

  Process {
    id: pasteProc
    command: ["wl-paste", "-n"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.editingRemote || !remoteField) return
        if (String(remoteField.text || "").trim() !== "") return
        var clip = String(text || "").trim()
        if (clip.indexOf("git@") === 0 || clip.indexOf("http://") === 0
            || clip.indexOf("https://") === 0 || clip.indexOf("ssh://") === 0)
          remoteField.text = clip
      }
    }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingRemote
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var k = String(t || "").toLowerCase()
        if (k === "s") root.runCli(["save"])
        else if (k === "p") root.pushStore()
        else if (k === "u") root.pullStore()
        else if (k === "g") root.startEditingRemote()
        else if (k === "r") root.runCli(["restore"])
        else if (k === "i") {
          var remote = setting("remote", "")
          if (remote !== "") root.runCli(["init", "--remote", remote])
          else root.runCli(["init"])
        }
        else if (k === "c") root.refresh()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: parent.width
          text: "oconfig"
          color: root.fg
          font.family: root.fontFam
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Text {
          width: parent.width
          text: Model.summaryLine(root.status)
          color: root.fg
          font.family: root.fontFam
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width
          visible: root.status.repo !== ""
          text: root.status.repo
          color: Qt.darker(root.fg, 1.5)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          wrapMode: Text.WrapAnywhere
        }

        Text {
          width: parent.width
          text: "Git remote"
          color: root.fg
          font.family: root.fontFam
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          width: parent.width
          visible: !root.editingRemote && (root.status.remote || setting("remote", "")) !== ""
          text: root.status.remote || setting("remote", "")
          color: Qt.darker(root.fg, 1.5)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          wrapMode: Text.WrapAnywhere
        }

        Button {
          visible: !root.editingRemote
          text: (root.status.remote || setting("remote", "")) !== ""
            ? "Change git remote"
            : "Set git remote"
          foreground: root.fg
          fontFamily: root.fontFam
          onClicked: root.startEditingRemote()
        }

        TextField {
          id: remoteField
          width: parent.width
          visible: root.editingRemote
          placeholderText: "git@github.com:YOU/omarchy-config.git"
          foreground: root.fg
          font.family: root.fontFam
          onAccepted: root.commitRemote()
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.cancelEditingRemote()
              event.accepted = true
            }
          }
        }

        Text {
          width: parent.width
          visible: root.editingRemote
          text: "Paste the URL, then Enter. Esc cancels."
          color: Qt.darker(root.fg, 1.5)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.status.lastCommit !== ""
          text: root.status.lastCommit
          color: Qt.darker(root.fg, 1.5)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          wrapMode: Text.WrapAnywhere
        }

        Repeater {
          model: root.status.untrackedPaths.slice(0, 8)

          Text {
            required property string modelData
            width: content.width
            text: modelData
            color: Color.accent
            font.family: root.fontFam
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAnywhere
          }
        }

        Text {
          width: parent.width
          visible: root.status.untrackedPaths.length > 8
          text: "+" + (root.status.untrackedPaths.length - 8) + " more"
          color: Qt.darker(root.fg, 1.5)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          visible: root.lastAction !== ""
          text: root.lastAction
          color: Qt.darker(root.fg, 1.5)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          wrapMode: Text.WrapAnywhere
        }

        Text {
          width: parent.width
          text: root.editingRemote
            ? "Enter save remote   Esc cancel"
            : (root.status.initialized
              ? "s save   p push   u pull   r restore   Esc"
              : "i init   Esc close")
          color: Qt.darker(root.fg, 1.5)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
