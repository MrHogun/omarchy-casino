import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Machine.js" as Machine
import "Roulette.js" as Roulette

// The casino: two games under one header.
//
// The panel is a container now — header, a switch between games, and whichever
// game is showing. It owns what both games share and nothing else: the sounds,
// the stats file, and which game you last had open.
//
// Styled the way the stock panels are rather than the way a casino is. No
// felt, no gold, no chrome. The colours are the theme's, the accent is spent
// only on what just won, and the odds are printed on both machines.
Panel {
  id: root
  moduleName: "mrhogun.slots"
  ipcTarget: "mrhogun.slots"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // ---- Which game. Remembered, because reopening the panel onto the other
  //      game every time is a small tax on the thing being a toy.
  readonly property string game: setting("game", "slots")
  readonly property bool onSlots: game !== "roulette"
  function selectGame(next) { root.persistSettings({ game: next }) }

  readonly property bool muted: setting("muted", false) === true
  function toggleMuted() { root.persistSettings({ muted: !root.muted }) }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---- Sound, shared. Two processes rather than one: an outcome overlaps the
  //      last tick of the thing that produced it.
  readonly property string soundDir: Qt.resolvedUrl("sounds").toString().replace("file://", "")

  Process { id: tickPlayer }
  Process { id: outcomePlayer }

  function play(name) {
    if (root.muted) return
    var player = name === "tick" ? tickPlayer : outcomePlayer
    if (player.running) return
    player.command = ["pw-play", "--volume=0.45", root.soundDir + "/" + name + ".wav"]
    player.running = true
  }

  // ---- Stats, one file for both games.
  //
  // In ~/.local/state rather than in the widget's shell.json entry: they move
  // on every spin, and rewriting the bar's own config that often to record a
  // toy's score is the wrong thing to churn. Atomic writes, so a spin landing
  // mid-save cannot leave half a file behind.
  readonly property string statsPath: Quickshell.env("HOME") + "/.local/state/omarchy/slots.json"

  FileView {
    id: statsFile
    path: root.statsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var loaded = JSON.parse(text()) || {}
        // The file used to be one flat slots tally, before there was a second
        // game to keep one for. A file in the old shape is read as the slots
        // half rather than discarded — nobody should lose four hundred spins
        // to a refactor.
        var slots = (loaded.slots !== undefined) ? loaded.slots
                  : (typeof loaded.spins === "number" ? loaded : null)
        if (slots && typeof slots.spins === "number") slotsView.stats = {
          spins: slots.spins || 0, wins: slots.wins || 0,
          jackpots: slots.jackpots || 0, streak: slots.streak || 0, worst: slots.worst || 0
        }
        var rl = loaded.roulette
        if (rl && typeof rl.spins === "number") rouletteView.stats = {
          spins: rl.spins || 0, wins: rl.wins || 0,
          straights: rl.straights || 0, streak: rl.streak || 0, worst: rl.worst || 0
        }
      } catch (e) {
        console.log("mrhogun.slots: stats unreadable, starting fresh: " + e)
      }
    }
  }

  function saveStats() {
    statsFile.setText(JSON.stringify({
      slots: slotsView.stats,
      roulette: rouletteView.stats
    }, null, 2) + "\n")
  }

  function resetStats() {
    slotsView.stats = Machine.emptyStats()
    slotsView.result = ""
    slotsView.reels = [Machine.IDLE, Machine.IDLE, Machine.IDLE]
    rouletteView.stats = Roulette.emptyStats()
    rouletteView.outcome = ""
    rouletteView.landed = -1
    if (root.hostWidget && "lastNumber" in root.hostWidget)
      root.hostWidget.lastNumber = -1
    if (root.hostWidget && "lastReels" in root.hostWidget)
      root.hostWidget.lastReels = slotsView.reels
    if (root.hostWidget && "lastWon" in root.hostWidget)
      root.hostWidget.lastWon = false
    root.saveStats()
  }

  readonly property bool spinning: onSlots ? slotsView.spinning : rouletteView.spinning
  readonly property int totalSpins: slotsView.stats.spins + rouletteView.stats.spins

  function spin() {
    if (root.onSlots) slotsView.spin()
    else rouletteView.spin()
  }

  // ---- Panel contract, the shape the stock panels use.
  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight + Style.space(28))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: root.spin()
      onCloseRequested: root.close()
    }

    Column {
      id: content
      anchors.centerIn: parent
      width: parent.width
      spacing: Style.space(14)

      PanelHero {
        width: parent.width
        title: "Casino"
        meta: root.onSlots
          ? (Machine.statsLabel(slotsView.stats) || "Nothing ventured")
          : (Roulette.statsLabel(rouletteView.stats) || "Nothing ventured")
        detail: root.onSlots
          ? Machine.jackpotBadge(slotsView.stats)
          : Roulette.straightBadge(rouletteView.stats)
        // Spinning dims the tally rather than replacing it: it does not stop
        // being true while the wheel turns, and swapping two strings of
        // different lengths made the line jump.
        metaOpacity: root.spinning ? 0.4 : 1.0
        Behavior on metaOpacity { NumberAnimation { duration: 180 } }
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily

        iconComponent: Component {
          Text {
            textFormat: Text.PlainText
            text: root.onSlots ? "7" : "0"
            color: root.onSlots
              ? (slotsView.won ? Color.accent : root.contentForeground)
              : (rouletteView.won ? Color.accent : "#00a22b")
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.display
          }
        }

        trailingControl: Component {
          Row {
            spacing: Style.space(4)

            PanelActionButton {
              iconText: "󰦛"
              tooltipText: "Reset both tallies"
              enabled: root.totalSpins > 0
              foreground: root.totalSpins > 0
                ? root.contentForeground
                : Qt.darker(root.contentForeground, 2.4)
              fontFamily: root.contentFontFamily
              fontSize: Style.font.display
              onClicked: root.resetStats()
            }

            PanelActionButton {
              iconText: root.muted ? "󰝟" : "󰕾"
              tooltipText: root.muted ? "Unmute" : "Mute"
              foreground: root.muted ? Qt.darker(root.contentForeground, 2.0) : root.contentForeground
              fontFamily: root.contentFontFamily
              fontSize: Style.font.display
              onClicked: root.toggleMuted()
            }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: Style.spacing.hairline
        color: root.contentForeground
        opacity: 0.1
      }

      // ---- The switch. Two words and a rule under the live one, rather than
      //      buttons: the panel has two games, not a navigation problem.
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(20)

        Repeater {
          model: [{ key: "slots", label: "SLOTS" }, { key: "roulette", label: "ROULETTE" }]

          Item {
            required property var modelData
            readonly property bool active: (modelData.key === "slots") === root.onSlots

            width: tabLabel.implicitWidth
            height: tabLabel.implicitHeight + Style.space(6)

            Text {
              id: tabLabel
              textFormat: Text.PlainText
              anchors.top: parent.top
              text: modelData.label
              color: active
                ? root.contentForeground
                : (tabMouse.containsMouse ? root.contentForeground : Qt.darker(root.contentForeground, 2.2))
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 2
            }

            Rectangle {
              anchors.bottom: parent.bottom
              width: parent.width
              height: Style.spacing.hairline
              color: Color.accent
              opacity: active ? 1.0 : 0.0
              Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            MouseArea {
              id: tabMouse
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              hoverEnabled: true
              // Switching mid-spin would leave a wheel turning behind a screen
              // you cannot watch it on.
              enabled: !root.spinning
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectGame(modelData.key)
            }
          }
        }
      }

      // ---- The games. Both stay alive rather than loading on demand:
      //      switching away and back should not reset the reels you left.
      Item {
        width: parent.width
        height: root.onSlots ? slotsView.implicitHeight : rouletteView.implicitHeight
        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
        clip: true

        SlotsView {
          id: slotsView
          width: parent.width
          visible: root.onSlots
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onRequestSound: function(name) { root.play(name) }
          onStatsUpdated: {
            root.saveStats()
            if (root.hostWidget) {
              if ("lastPlayed" in root.hostWidget) root.hostWidget.lastPlayed = "slots"
              if ("lastReels" in root.hostWidget) root.hostWidget.lastReels = slotsView.reels
              if ("lastWon" in root.hostWidget) root.hostWidget.lastWon = slotsView.won
            }
          }
        }

        RouletteView {
          id: rouletteView
          width: parent.width
          visible: !root.onSlots
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          onRequestSound: function(name) { root.play(name) }
          onStatsUpdated: {
            root.saveStats()
            if (root.hostWidget) {
              if ("lastPlayed" in root.hostWidget) root.hostWidget.lastPlayed = "roulette"
              if ("lastNumber" in root.hostWidget)
                root.hostWidget.lastNumber = rouletteView.landed
              if ("lastNumberColor" in root.hostWidget)
                root.hostWidget.lastNumberColor = rouletteView.landed >= 0
                  ? rouletteView.barColorFor(rouletteView.landed)
                  : root.contentForeground
              if ("lastWon" in root.hostWidget)
                root.hostWidget.lastWon = rouletteView.won
            }
          }
        }
      }
    }
  }
}
