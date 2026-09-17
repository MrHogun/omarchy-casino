import QtQuick
import qs.Commons
import qs.Ui
import "Roulette.js" as Roulette

// Roulette, as a strip rather than a disc.
//
// A drawn wheel in a 380px panel gives each of 37 pockets about ten degrees,
// which is a ring of illegible numbers — and rotating text to match only makes
// it worse. The strip is what every digital table uses instead: the same
// pockets in the same wheel order, run past a fixed marker. It reads at this
// width, it decelerates convincingly, and the numbers blurring past are the
// ones the real wheel would show, because the order is the real one.
Item {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property var stats: Roulette.emptyStats()

  // The panel owns audio; the view only says when something happened.
  signal requestSound(string name)
  signal statsUpdated()

  property string betKey: "red"
  property int chosenNumber: 7
  property int landed: -1
  property bool spinning: false
  property string outcome: ""

  readonly property bool won: outcome === "WON" || outcome === "STRAIGHT UP"

  // Stepped, not slid. The strip moves one pocket at a time and each step is
  // the tick you hear — a continuous slide had the sound running on its own
  // timer beside the motion, which is why the two never quite agreed.
  property int stepIndex: 0
  property int stepCount: 0
  readonly property int travelMs: 3200
  readonly property var pockets: Roulette.strip()
  readonly property int cellWidth: Style.space(44)
  readonly property int lapPixels: Roulette.lapLength() * cellWidth

  implicitHeight: column.implicitHeight

  function colorFor(n) {
    var c = Roulette.colorOf(n)
    if (c === "green") return "#00a22b"
    if (c === "red") return "#e64343"
    return Qt.darker(root.foreground, 3.0)
  }

  // The same colours, but for the bar. On the strip a black pocket is drawn
  // dimmed against its neighbours; in the bar that same dimming would be a
  // number nobody can read, so there it wears the bar's own ink.
  function barColorFor(n) {
    var c = Roulette.colorOf(n)
    if (c === "green") return "#00a22b"
    if (c === "red") return "#e64343"
    return root.foreground
  }

  // Where the strip sits between spins: the resting lap, with the pocket
  // under the marker.
  readonly property real restBase: viewport.width / 2
    - (Roulette.stripRestIndex(root.landed >= 0 ? root.landed : 0) * root.cellWidth
       + root.cellWidth / 2)

  function spin() {
    if (root.spinning) return
    root.spinning = true
    root.outcome = ""

    var number = Roulette.randomPocket()
    var from = root.landed >= 0 ? root.landed : 0

    // Always at least one full lap, then however much further the target
    // sits. Without the lap a pocket two along from the last one would be a
    // two-step twitch rather than a spin.
    var delta = (Roulette.wheelIndex(number) - Roulette.wheelIndex(from) + 37) % 37
    root.stepCount = 37 + delta
    root.stepIndex = 0

    root.landed = -1
    settle.pocket = number
    stepTimer.interval = root.stepInterval(0)
    stepTimer.restart()
  }

  // The schedule that makes it decelerate and still take the same time
  // whatever distance it has to cover. Positions are eased, not intervals:
  // step k lands at travelMs·(1 − √(1 − k/steps)), so the gaps between them
  // stretch on their own and the last one is the long, deciding pause.
  function stepInterval(k) {
    if (root.stepCount <= 0) return 40
    var t0 = root.travelMs * (1 - Math.sqrt(1 - k / root.stepCount))
    var t1 = root.travelMs * (1 - Math.sqrt(1 - (k + 1) / root.stepCount))
    return Math.max(16, Math.round(t1 - t0))
  }

  Timer {
    id: stepTimer
    repeat: false
    onTriggered: {
      root.stepIndex++
      strip.x = root.restBase - root.stepIndex * root.cellWidth
      root.requestSound("tick")

      if (root.stepIndex >= root.stepCount) { settle.apply(); return }
      interval = root.stepInterval(root.stepIndex)
      restart()
    }
  }

  QtObject {
    id: settle
    property int pocket: 0

    function apply() {
      stepTimer.stop()
      root.landed = settle.pocket
      root.outcome = Roulette.resultLabel(root.betKey, settle.pocket, root.chosenNumber)
      var didWin = Roulette.wins(root.betKey, settle.pocket, root.chosenNumber)
      var straight = root.betKey === "number" && didWin
      root.stats = Roulette.recordSpin(root.stats, didWin, straight)
      root.spinning = false
      root.statsUpdated()
      if (straight) root.requestSound("jackpot")
      else if (didWin) root.requestSound("win")

      // One lap was travelled, so one lap comes back. The copies are
      // identical, so nothing moves on screen, and the next spin starts with
      // the same runway as this one had.
      strip.x = root.restBase
    }
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(12)

    // ---- The strip.
    Item {
      id: viewport
      width: parent.width
      height: Style.space(52)
      clip: true

      Row {
        id: strip
        height: parent.height
        spacing: 0
        // Opens resting on the zero of the second lap, so there is a full lap
        // of wheel to the left of the marker rather than an empty half.
        x: root.restBase

        Repeater {
          model: root.pockets

          Item {
            required property var modelData
            width: root.cellWidth
            height: strip.height

            Rectangle {
              anchors.centerIn: parent
              width: root.cellWidth - Style.space(4)
              height: parent.height - Style.space(10)
              radius: Style.cornerRadius
              color: "transparent"
              border.width: Style.spacing.hairline
              border.color: root.colorFor(modelData)
              opacity: 0.85

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: modelData
                color: root.colorFor(modelData)
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
              }
            }
          }
        }
      }

      // The ends fade into the panel instead of being cut off at the
      // viewport edge. A hard edge says the strip stops there; a fade says it
      // carries on past the frame, which is what a wheel does — and it is the
      // difference between a moving list and something turning.
      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.space(30)
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: Color.popups.background }
          GradientStop { position: 1.0; color: "transparent" }
        }
      }

      Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.space(30)
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 1.0; color: Color.popups.background }
        }
      }

      // The marker. Full height and accent, so the pocket under it is never
      // ambiguous — which matters most in the last half-second.
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.max(1, Style.spacing.hairline * 2)
        color: Color.accent
      }
    }

    // ---- Outcome. Holds its line whether or not there is one, so the panel
    //      does not jump when a spin resolves.
    Item {
      width: parent.width
      height: outcomeText.implicitHeight

      Text {
        id: outcomeText
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: root.spinning
          ? "…"
          : (root.landed < 0
              ? " "
              : (root.landed + "   " + (root.outcome || "")))
        color: root.won ? Color.accent : Qt.darker(root.foreground, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.letterSpacing: 1
      }
    }

    Rectangle {
      width: parent.width
      height: Style.spacing.hairline
      color: root.foreground
      opacity: 0.1
    }

    // ---- The bet. Chips rather than a table: seven targets that fit, instead
    //      of a forty-target board that does not.
    Flow {
      width: parent.width
      spacing: Style.space(5)

      Repeater {
        model: Roulette.BETS

        Rectangle {
          required property var modelData
          readonly property bool active: root.betKey === modelData.key

          width: chipLabel.implicitWidth + Style.space(14)
          height: chipLabel.implicitHeight + Style.space(8)
          radius: Style.cornerRadius
          color: active ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
          border.width: Style.spacing.hairline
          border.color: active
            ? Color.accent
            : Style.normalBorderFor(root.foreground, root.foreground)
          opacity: root.spinning ? 0.45 : 1.0

          Text {
            id: chipLabel
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: modelData.label
            color: {
              if (modelData.key === "red") return active ? Color.accent : "#e64343"
              if (modelData.key === "black") return active ? Color.accent : Qt.darker(root.foreground, 2.2)
              return active ? Color.accent : root.foreground
            }
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }

          MouseArea {
            anchors.fill: parent
            enabled: !root.spinning
            cursorShape: Qt.PointingHandCursor
            onClicked: root.betKey = modelData.key
          }
        }
      }
    }

    // ---- The number, only when a straight-up bet is what is on the table.
    Item {
      width: parent.width
      height: root.betKey === "number" ? numberRow.implicitHeight : 0
      visible: root.betKey === "number"
      clip: true

      Row {
        id: numberRow
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(10)

        PanelActionButton {
          iconText: "󰅁"
          tooltipText: "Lower"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: !root.spinning
          onClicked: root.chosenNumber = (root.chosenNumber + 36) % 37
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(40)
          horizontalAlignment: Text.AlignHCenter
          text: root.chosenNumber
          color: root.colorFor(root.chosenNumber)
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
        }

        PanelActionButton {
          iconText: "󰅂"
          tooltipText: "Higher"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: !root.spinning
          onClicked: root.chosenNumber = (root.chosenNumber + 1) % 37
        }
      }
    }

    // ---- Spin.
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
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

    // ---- The odds of whatever is currently on the table.
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: {
        var bet = Roulette.betFor(root.betKey)
        if (!bet) return ""
        var pct = Math.round(bet.chance * 1000) / 10
        return bet.odds + "   ·   " + pct + "% OF SPINS"
      }
      color: Qt.darker(root.foreground, 2.1)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
    }
  }
}
