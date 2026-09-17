import QtQuick
import qs.Commons
import qs.Ui
import "Blackjack.js" as Blackjack

// The blackjack table.
//
// Same vocabulary as the other two: a card is the reel cell and the roulette
// pocket again — a bordered box with one glyph in it — so three games share a
// shape instead of inventing three. Cards carry no suit, because nothing in
// blackjack does.
Item {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property var stats: Blackjack.emptyStats()

  signal requestSound(string name)
  signal statsUpdated()

  property var shoe: []
  property var playerCards: []
  property var dealerCards: []
  property bool inHand: false
  property bool holeDown: true
  property bool doubled: false
  property string result: ""

  readonly property bool won: Blackjack.isWin(result)
  readonly property string resultLabel: result === "" ? "" : Blackjack.outcomeLabel(result)
  readonly property bool canDouble: inHand && playerCards.length === 2

  readonly property int cardWidth: Style.space(42)
  readonly property int cardHeight: Style.space(58)

  implicitHeight: column.implicitHeight

  function cardColor(card) {
    if (!card) return Qt.darker(root.foreground, 2.4)
    // A red card is red; a black one is the panel's own ink. Dimming the black
    // ones to "not red" would make half the shoe look like it was face down.
    return card.red ? "#e64343" : root.foreground
  }

  function draw() {
    if (Blackjack.needsShuffle(root.shoe)) root.shoe = Blackjack.newShoe()
    var next = root.shoe.slice()
    var card = next.pop()
    root.shoe = next
    return card
  }

  function deal() {
    if (root.inHand) return
    root.result = ""
    root.doubled = false
    root.holeDown = true
    root.playerCards = [draw(), draw()]
    root.dealerCards = [draw(), draw()]
    root.inHand = true
    root.requestSound("tick")

    // A natural resolves itself; there is nothing to decide and sitting on the
    // buttons waiting for a HIT that cannot help would be theatre.
    if (Blackjack.isBlackjack(root.playerCards) || Blackjack.isBlackjack(root.dealerCards))
      finish()
  }

  function hit() {
    if (!root.inHand) return
    root.playerCards = root.playerCards.concat([draw()])
    root.requestSound("tick")
    if (Blackjack.isBust(root.playerCards)) finish()
  }

  function stand() {
    if (!root.inHand) return
    finish()
  }

  // Without stakes a double is not a bet, it is a commitment: exactly one more
  // card and the hand is over. That still changes what you should do, which is
  // the part worth keeping.
  function doubleDown() {
    if (!root.canDouble) return
    root.doubled = true
    root.playerCards = root.playerCards.concat([draw()])
    root.requestSound("tick")
    finish()
  }

  function finish() {
    root.holeDown = false

    // The dealer only plays out a hand that is still live. Drawing to a busted
    // player is a ritual the house performs for the cameras, not a rule.
    if (!Blackjack.isBust(root.playerCards)) {
      var cards = root.dealerCards.slice()
      while (Blackjack.dealerShouldHit(cards)) cards.push(draw())
      root.dealerCards = cards
    }

    root.result = Blackjack.settle(root.playerCards, root.dealerCards)
    root.stats = Blackjack.recordHand(root.stats, root.result)
    root.inHand = false
    root.statsUpdated()

    if (root.result === "blackjack") root.requestSound("jackpot")
    else if (root.result === "win") root.requestSound("win")
  }

  // ---- One row of cards, dealer or player.
  component Hand: Row {
    id: hand
    property var cards: []
    property bool hideSecond: false
    spacing: Style.space(6)

    Repeater {
      model: hand.cards

      Rectangle {
        id: card
        required property var modelData
        required property int index

        readonly property bool facedown: hand.hideSecond && index === 1

        width: root.cardWidth
        height: root.cardHeight
        radius: Style.cornerRadius
        color: "transparent"
        border.width: Style.spacing.hairline
        border.color: facedown
          ? Style.normalBorderFor(root.foreground, root.foreground)
          : root.cardColor(modelData)

        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: facedown ? "◇" : Blackjack.rankLabel(modelData)
          color: facedown ? Qt.darker(root.foreground, 2.4) : root.cardColor(modelData)
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
        }

        // Dealt rather than simply present: a card fades up into its place.
        // Short, because the pace of the game is the player's, not an
        // animation's.
        //
        // Both animations name the card by id. `target: parent` reads as the
        // obvious thing to write and is not: an animation is not a visual
        // item, so its `parent` resolves to nothing, the opacity is never
        // raised off zero, and every card deals face down into thin air —
        // which is exactly how this first rendered.
        opacity: 0
        transform: Translate { id: lift; y: Style.space(6) }
        Component.onCompleted: { dealIn.start(); liftIn.start() }

        NumberAnimation {
          id: dealIn
          target: card
          property: "opacity"
          from: 0; to: 1
          duration: 170
          easing.type: Easing.OutQuad
        }

        NumberAnimation {
          id: liftIn
          target: lift
          property: "y"
          from: Style.space(6); to: 0
          duration: 170
          easing.type: Easing.OutQuad
        }
      }
    }
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    // ---- Dealer.
    Item {
      width: parent.width
      height: Math.max(dealerHand.implicitHeight, dealerLabel.implicitHeight)

      Text {
        id: dealerLabel
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "DEALER   " + Blackjack.totalLabel(root.dealerCards, root.holeDown)
        color: Qt.darker(root.foreground, 1.7)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
      }

      Hand {
        id: dealerHand
        anchors.right: parent.right
        cards: root.dealerCards
        hideSecond: root.holeDown
      }
    }

    // ---- Player.
    Item {
      width: parent.width
      height: Math.max(playerHand.implicitHeight, playerLabel.implicitHeight)

      Text {
        id: playerLabel
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "YOU   " + Blackjack.totalLabel(root.playerCards, false)
          + (root.doubled ? "   DOUBLED" : "")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
      }

      Hand {
        id: playerHand
        anchors.right: parent.right
        cards: root.playerCards
      }
    }

    // ---- Outcome, holding its line so the table does not jump.
    Item {
      width: parent.width
      height: outcomeText.implicitHeight

      Text {
        id: outcomeText
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: root.resultLabel || " "
        color: root.won
          ? Color.accent
          : (root.result === "push" ? Qt.darker(root.foreground, 1.6) : Qt.darker(root.foreground, 1.6))
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.letterSpacing: root.result === "blackjack" ? 6 : 1
        Behavior on font.letterSpacing { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
      }
    }

    Rectangle {
      width: parent.width
      height: Style.spacing.hairline
      color: root.foreground
      opacity: 0.1
    }

    // ---- Actions. One row, and only what is legal right now is live.
    component TableAction: Item {
      id: action
      property string label: ""
      property bool live: true
      signal triggered()

      width: actionText.implicitWidth
      height: actionText.implicitHeight + Style.space(6)

      Text {
        id: actionText
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: action.label
        color: !action.live
          ? Qt.darker(root.foreground, 2.6)
          : (actionMouse.containsMouse ? Color.accent : root.foreground)
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.letterSpacing: 3
      }

      MouseArea {
        id: actionMouse
        anchors.fill: parent
        anchors.margins: -Style.space(6)
        hoverEnabled: action.live
        enabled: action.live
        cursorShape: action.live ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: action.triggered()
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(18)

      TableAction {
        label: "DEAL"
        visible: !root.inHand
        live: !root.inHand
        onTriggered: root.deal()
      }

      TableAction {
        label: "HIT"
        visible: root.inHand
        live: root.inHand
        onTriggered: root.hit()
      }

      TableAction {
        label: "STAND"
        visible: root.inHand
        live: root.inHand
        onTriggered: root.stand()
      }

      TableAction {
        label: "DOUBLE"
        visible: root.inHand
        live: root.canDouble
        onTriggered: root.doubleDown()
      }
    }

    // ---- The rules, stated. Same as the odds on the other two machines: a
    //      table that does not say which soft-17 rule it runs is hiding two
    //      tenths of a percent from you.
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: Blackjack.rulesLabel()
      color: Qt.darker(root.foreground, 2.1)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
    }
  }
}
