import QtQuick
import Quickshell
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

  readonly property bool won: result === "three" || result === "jackpot"
  readonly property string resultLabel: result === "" ? "" : Machine.outcomeLabel(result)

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

    if (next[0] && next[1] && next[2]) {
      reelTick.stop()
      root.spinning = false
      root.result = Machine.outcome(root.reels)
      root.stats = Machine.recordSpin(root.stats, root.result)
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

    // ---- Title. Small caps and letter-spaced, the way the stock panels
    //      label a section, rather than a machine's nameplate.
    Text {
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      text: "SLOTS"
      color: Qt.darker(root.contentForeground, 1.4)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 2
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
        font.letterSpacing: 1
        opacity: root.spinning ? 0.6 : 1.0
        Behavior on opacity { NumberAnimation { duration: 150 } }
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

    Text {
      textFormat: Text.PlainText
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      visible: text !== ""
      text: Machine.statsLabel(root.stats)
      color: Qt.darker(root.contentForeground, 1.8)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
    }
  }

  }
}
