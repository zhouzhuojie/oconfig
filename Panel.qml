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
    })
  }

  function close() {
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
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "s" || t === "S") root.runCli(["save"])
        else if (t === "p" || t === "P") root.pushStore()
        else if (t === "u" || t === "U") root.pullStore()
        else if (t === "r" || t === "R") root.runCli(["restore"])
        else if (t === "i" || t === "I") {
          var remote = setting("remote", "")
          if (remote !== "") root.runCli(["init", "--remote", remote])
          else root.runCli(["init"])
        }
        else if (t === "c" || t === "C") root.refresh()
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
          visible: (root.status.remote || setting("remote", "")) !== ""
          text: root.status.remote || setting("remote", "")
          color: Qt.darker(root.fg, 1.5)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          wrapMode: Text.WrapAnywhere
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
          text: root.status.initialized
            ? "s save   p push   u pull   r restore   c refresh   Esc close"
            : "i init   c refresh   Esc close"
          color: Qt.darker(root.fg, 1.5)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
