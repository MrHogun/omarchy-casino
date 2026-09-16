import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Machine.js" as Machine

// The machine itself: three reels, a spin, and what it has cost you so far.
//
// Styled the way the stock panels are rather than the way a slot machine is —
// no cabinet, no gold, no chrome. The reels are three quiet cells on the same
// spacing scale as the calendar's day grid, and the only colour in the panel
// is the theme's accent, spent on the one line that has just won.
//
// BarWidget.qml owns the bar label and hands this panel the button to anchor
// against.
Panel {
  id: root
  moduleName: "mrhogun.slots"
  ipcTarget: "mrhogun.slots"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Machine state.
  property var reels: [Machine.IDLE, Machine.IDLE, Machine.IDLE]
  property var locked: [false, false, false]
  property bool spinning: false
  property string result: ""
  property var stats: Machine.emptyStats()

  // Stats live in a state file rather than in the widget's shell.json entry.
  // They change on every spin, and rewriting the bar's own config that often
  // to record a toy's score would be the wrong thing to churn. Atomic writes,
  // so a spin landing mid-save cannot leave half a file behind.
  readonly property string statsPath: Quickshell.env("HOME") + "/.local/state/omarchy/slots.json"

  FileView {
    id: statsFile
    path: root.statsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var loaded = JSON.parse(text())
        // Guard the shape rather than trusting the file: it is editable, and
        // a hand-mangled one should reset the tally, not break the panel.
        if (loaded && typeof loaded.spins === "number")
          root.stats = {
            spins: loaded.spins || 0,
            wins: loaded.wins || 0,
            jackpots: loaded.jackpots || 0,
            streak: loaded.streak || 0,
            worst: loaded.worst || 0
          }
      } catch (e) {
        console.log("mrhogun.slots: stats unreadable, starting fresh: " + e)
      }
    }
  }

  function resetStats() {
    root.stats = Machine.emptyStats()
    root.result = ""
    root.reels = [Machine.IDLE, Machine.IDLE, Machine.IDLE]
    if (root.hostWidget && "lastReels" in root.hostWidget)
      root.hostWidget.lastReels = root.reels
    if (root.hostWidget && "lastWon" in root.hostWidget)
      root.hostWidget.lastWon = false
    root.saveStats()
  }

  function saveStats() {
    statsFile.setText(JSON.stringify(root.stats, null, 2) + "\n")
  }

  readonly property bool won: result === "three" || result === "jackpot"
  readonly property string resultLabel: result === "" ? "" : Machine.outcomeLabel(result)

  // Muted rides in the widget's own shell.json entry, so a machine silenced
  // once stays silenced. It is the only thing here worth persisting — the
  // stats are a toy and a toy that survives reboots starts to feel like a
  // ledger.
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

  readonly property string soundDir: Qt.resolvedUrl("sounds").toString().replace("file://", "")

  // Two processes rather than one: a reel tick lands 360ms before the next,
  // which is comfortable, but the outcome sound overlaps the final tick and
  // reusing a single running process would drop one of them.
  Process { id: tickPlayer }
  Process { id: outcomePlayer }

  function play(player, name) {
    if (root.muted || player.running) return
    player.command = ["pw-play", "--volume=0.45", root.soundDir + "/" + name + ".wav"]
    player.running = true
  }

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int reelWidth: Style.space(64)
  readonly property int reelHeight: Style.space(78)

  // Each reel runs longer than the one before it. That stagger is the whole
  // reason a slot machine is watchable: stopping them together would resolve
  // the question all at once, and the third reel is where the suspense is.
  readonly property var stopDelays: [620, 980, 1400]

  function spin() {
    if (root.spinning) return
    root.spinning = true
    root.result = ""
    root.locked = [false, false, false]
    reelTick.start()
    stopOne.restart()
    stopTwo.restart()
    stopThree.restart()
  }

  function lockReel(index) {
    var next = root.locked.slice()
    next[index] = true
    root.locked = next
    root.play(tickPlayer, "tick")

    if (next[0] && next[1] && next[2]) {
      reelTick.stop()
      root.spinning = false
      root.result = Machine.outcome(root.reels)
      root.stats = Machine.recordSpin(root.stats, root.result)
      root.saveStats()
      // Only a win is worth a sound of its own. A losing spin already got
      // three ticks, and giving it a fourth noise would be the machine
      // congratulating you for nothing.
      if (root.result === "jackpot") root.play(outcomePlayer, "jackpot")
      else if (root.result === "three") root.play(outcomePlayer, "win")
      if (root.hostWidget) {
        if ("lastReels" in root.hostWidget) root.hostWidget.lastReels = root.reels
        if ("lastWon" in root.hostWidget) root.hostWidget.lastWon = root.won
      }
    }
  }

  // One timer drives every unlocked reel rather than one timer each: they are
  // meant to blur at the same rate, and three independent tickers drift apart
  // visibly within a second.
  Timer {
    id: reelTick
    interval: 60
    repeat: true
    onTriggered: {
      var next = root.reels.slice()
      for (var i = 0; i < 3; i++)
        if (!root.locked[i]) next[i] = Machine.randomSymbol()
      root.reels = next
    }
  }

  Timer { id: stopOne;   interval: root.stopDelays[0]; onTriggered: root.lockReel(0) }
  Timer { id: stopTwo;   interval: root.stopDelays[1]; onTriggered: root.lockReel(1) }
  Timer { id: stopThree; interval: root.stopDelays[2]; onTriggered: root.lockReel(2) }

  // ---- Panel contract, same shape the stock panels use.
  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    // Anchored under the widget rather than centred on the bar: the panel
    // belongs to an icon sitting on the right, and a popup that opens in the
    // middle of the screen loses the thread back to what opened it.
    centerOnBar: false
    focusTarget: keyCatcher
    // The same fixed width every stock right-hand panel uses — bluetooth,
    // network and audio all pass Style.space(380). Deriving it from the
    // content instead made this one narrower than its neighbours and it sat
    // differently for it.
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight + Style.space(28))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Space and Return both spin, because both are what a hand reaches for
      // when the thing on screen is a lever.
      onActivateRequested: root.spin()
      onCloseRequested: root.close()
    }

  Column {
    id: content
    anchors.centerIn: parent
    spacing: Style.space(14)
    // Filling the panel rather than sizing it: the width is the panel's now,
    // and the children centre inside it.
    width: parent.width

    // ---- Header, on the shell's own PanelHero — the same component the
    //      tailscale, dropbox and agents panels use, so the title sits where
    //      a title sits everywhere else and the mute rides in the slot meant
    //      for a trailing control. Hand-rolling it was what made this corner
    //      look unlike the rest of the desktop.
    PanelHero {
      width: parent.width
      title: "Slots"
      // The meta line carries the running tally, which is why the stats no
      // longer need a row of their own at the bottom.
      //
      // Spinning dims this rather than replacing it. The tally does not stop
      // being true while the reels turn, so swapping it out loses a fact to
      // say something the reels are already saying — and swapping two strings
      // of different lengths made the line jump. Dimming is the whole signal.
      meta: Machine.statsLabel(root.stats) || "Nothing ventured"
      detail: Machine.jackpotBadge(root.stats)
      metaOpacity: root.spinning ? 0.4 : 1.0
      Behavior on metaOpacity { NumberAnimation { duration: 180 } }
      foreground: root.contentForeground
      fontFamily: root.contentFontFamily

      iconComponent: Component {
        Text {
          textFormat: Text.PlainText
          text: "7"
          color: root.won ? Color.accent : root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.display
        }
      }

      // Both controls sized to the hero's own icon. At the button default of
      // Style.font.icon they read as afterthoughts next to a 24px glyph; at
      // the hero's size the header balances, an icon at each end.
      trailingControl: Component {
        Row {
          spacing: Style.space(4)

          PanelActionButton {
            iconText: "󰦛"
            tooltipText: "Reset the tally"
            // Dimmed until there is something to undo, so the control says
            // whether it would do anything before you press it.
            enabled: root.stats.spins > 0
            foreground: root.stats.spins > 0
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

    // The hairline the stock panels rule under their hero, so the header
    // reads as a header here too and not as the first item of a list.
    Rectangle {
      width: parent.width
      height: Style.spacing.hairline
      color: root.contentForeground
      opacity: 0.1
    }

    // ---- The reels.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(8)

      Repeater {
        model: 3

        Rectangle {
          id: reel
          required property int index

          readonly property bool settled: !root.spinning && root.result !== ""

          width: root.reelWidth
          height: root.reelHeight
          radius: Style.cornerRadius
          color: "transparent"
          // A winning row is the one place the panel raises its voice, and it
          // does it with a border rather than a fill — the same restraint the
          // calendar uses to mark today.
          border.width: Style.spacing.hairline
          border.color: reel.settled && root.won
            ? Color.accent
            : Style.normalBorderFor(root.contentForeground, root.contentForeground)

          // The jackpot's own flourish: a swell that rolls left to right and
          // comes back round three times. Scale rather than colour, because
          // the border and glyph have already gone accent by then and a
          // second colour change would land on top of the first.
          SequentialAnimation {
            id: jackpotPulse
            loops: 3
            PauseAnimation { duration: reel.index * 90 }
            NumberAnimation {
              target: reel; property: "scale"; to: 1.14
              duration: 150; easing.type: Easing.OutQuad
            }
            NumberAnimation {
              target: reel; property: "scale"; to: 1.0
              duration: 240; easing.type: Easing.OutBack
            }
            PauseAnimation { duration: (2 - reel.index) * 90 }
          }

          Connections {
            target: root
            function onResultChanged() {
              if (root.result === "jackpot") jackpotPulse.restart()
            }
          }

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: root.reels[reel.index]
            color: reel.settled && root.won
              ? Color.accent
              : (root.reels[reel.index] === Machine.IDLE
                  ? Qt.darker(root.contentForeground, 2.2)
                  : root.contentForeground)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.displayLarge

            // The blur is done by opacity rather than by a shader: a symbol
            // swapped every 60ms already reads as motion, and dimming it is
            // what stops the eye trying to read each one.
            opacity: root.spinning && !root.locked[reel.index] ? 0.55 : 1.0
            Behavior on opacity { NumberAnimation { duration: 120 } }
          }
        }
      }
    }

    // ---- Outcome. The line holds its height whether or not there is
    //      anything to say, so pressing spin does not make the panel jump.
    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      width: outcome.implicitWidth
      height: outcome.implicitHeight

      Text {
        id: outcome
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: root.spinning ? "…" : (root.resultLabel || " ")
        color: root.won ? Color.accent : Qt.darker(root.contentForeground, 1.6)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        opacity: root.spinning ? 0.6 : 1.0
        Behavior on opacity { NumberAnimation { duration: 150 } }

        // Every other outcome sits at 1. The jackpot's letters push apart and
        // stay there — the word itself becoming the announcement, which is
        // about as much noise as this panel is willing to make.
        font.letterSpacing: 1
        SequentialAnimation {
          id: jackpotWord
          NumberAnimation {
            target: outcome; property: "font.letterSpacing"
            from: 1; to: 7; duration: 420; easing.type: Easing.OutCubic
          }
        }
        Connections {
          target: root
          function onResultChanged() {
            if (root.result === "jackpot") jackpotWord.restart()
            else outcome.font.letterSpacing = 1
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

    // ---- Spin. A word rather than an icon: it is the only action here, and
    //      naming it costs one line and removes all doubt.
    Text {
      id: spinLabel
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.spinning ? "SPINNING" : "SPIN"
      color: root.spinning
        ? Qt.darker(root.contentForeground, 2.0)
        : (spinMouse.containsMouse ? Color.accent : root.contentForeground)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.subtitle
      font.letterSpacing: 3

      MouseArea {
        id: spinMouse
        anchors.fill: parent
        anchors.margins: -Style.space(8)
        hoverEnabled: true
        enabled: !root.spinning
        cursorShape: root.spinning ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: root.spin()
      }
    }

    // ---- The odds, stated. A machine that hides them is the other kind.
    Text {
      textFormat: Text.PlainText
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: Machine.oddsLabel()
      color: Qt.darker(root.contentForeground, 2.1)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
    }

  }

  }
}
