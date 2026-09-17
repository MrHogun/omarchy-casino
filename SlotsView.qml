import QtQuick
import qs.Commons
import qs.Ui
import "Machine.js" as Machine

// The slot machine, lifted out of Panel.qml when roulette arrived so the panel
// could go back to being a container. Everything here was already written and
// is unchanged in behaviour — the reels, the stagger, the jackpot swell.
Item {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property var stats: Machine.emptyStats()

  signal requestSound(string name)
  signal statsUpdated()

  property var reels: [Machine.IDLE, Machine.IDLE, Machine.IDLE]
  property var locked: [false, false, false]
  property bool spinning: false
  property string result: ""

  readonly property bool won: result === "three" || result === "jackpot"
  readonly property string resultLabel: result === "" ? "" : Machine.outcomeLabel(result)

  readonly property int reelWidth: Style.space(64)
  readonly property int reelHeight: Style.space(78)
  readonly property var stopDelays: [620, 980, 1400]

  implicitHeight: column.implicitHeight

  function spin() {
    if (root.spinning) return
    root.spinning = true
    root.result = ""
    root.locked = [false, false, false]
    reelTick.start()
    stopOne.restart(); stopTwo.restart(); stopThree.restart()
  }

  function lockReel(index) {
    var next = root.locked.slice()
    next[index] = true
    root.locked = next
    root.requestSound("tick")

    if (next[0] && next[1] && next[2]) {
      reelTick.stop()
      root.spinning = false
      root.result = Machine.outcome(root.reels)
      root.stats = Machine.recordSpin(root.stats, root.result)
      root.statsUpdated()
      if (root.result === "jackpot") root.requestSound("jackpot")
      else if (root.result === "three") root.requestSound("win")
    }
  }

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

  Column {
    id: column
    width: parent.width
    spacing: Style.space(14)

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
            : Style.normalBorderFor(root.foreground, root.foreground)

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
                  ? Qt.darker(root.foreground, 2.2)
                  : root.foreground)
            font.family: root.fontFamily
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
        color: root.won ? Color.accent : Qt.darker(root.foreground, 1.6)
        font.family: root.fontFamily
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
      color: root.foreground
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
        ? Qt.darker(root.foreground, 2.0)
        : (spinMouse.containsMouse ? Color.accent : root.foreground)
      font.family: root.fontFamily
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
      color: Qt.darker(root.foreground, 2.1)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
    }


  }
}
