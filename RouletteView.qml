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

  function restX(number) {
    return viewport.width / 2 - (Roulette.stripRestIndex(number) * root.cellWidth + root.cellWidth / 2)
  }

  function spin() {
    if (root.spinning) return
    root.spinning = true
    root.outcome = ""

    var number = Roulette.randomPocket()
    var index = Roulette.stripLandingIndex(number)
    var target = viewport.width / 2 - (index * root.cellWidth + root.cellWidth / 2)

    root.landed = -1
    slide.to = target
    slide.restart()
    ballTick.interval = 40
    ballTick.restart()

    settle.pocket = number
  }

  // The ball, slowing as the wheel does. Each tick stretches the gap to the
  // next by a tenth, which is what a decelerating clatter sounds like — a
  // fixed interval would sound like a metronome bolted to a wheel.
  Timer {
    id: ballTick
    repeat: true
    interval: 40
    onTriggered: {
      root.requestSound("tick")
      interval = Math.round(interval * 1.11)
      if (interval > 420) stop()
    }
  }

  NumberAnimation {
    id: slide
    target: strip
    property: "x"
    duration: 3400
    // Quint rather than Cubic: the last second should crawl, because that is
    // where the whole thing is decided.
    easing.type: Easing.OutQuint
    onFinished: settle.apply()
  }

  QtObject {
    id: settle
    property int pocket: 0

    function apply() {
      ballTick.stop()
      root.landed = settle.pocket
      root.outcome = Roulette.resultLabel(root.betKey, settle.pocket, root.chosenNumber)
      var didWin = Roulette.wins(root.betKey, settle.pocket, root.chosenNumber)
      var straight = root.betKey === "number" && didWin
      root.stats = Roulette.recordSpin(root.stats, didWin, straight)
      root.spinning = false
      root.statsUpdated()
      if (straight) root.requestSound("jackpot")
      else if (didWin) root.requestSound("win")

      // Shift back the laps just travelled. The copies are identical, so this
      // is invisible, and it hands the next spin the same runway.
      strip.x += Roulette.settleShift() * root.cellWidth
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
        x: viewport.width / 2 - (Roulette.stripRestIndex(0) * root.cellWidth + root.cellWidth / 2)

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
