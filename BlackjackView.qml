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
//
// The player is an array of hands rather than one hand, because splitting is
// the rule that makes this blackjack rather than a card-drawing toy, and
// bolting a second hand onto a single-hand table is how that goes wrong.
Item {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property var stats: Blackjack.emptyStats()

  signal requestSound(string name)
  signal statsUpdated()

  property var shoe: []
  // Each entry: { cards, doubled, done, fromSplit, frozen, result }
  property var hands: []
  property int activeIndex: 0
  property var dealerCards: []
  property bool inHand: false
  property bool holeDown: true
  property bool settled: false
  // The dealer's turn is its own state. Between the hole card turning over and
  // the last card landing nobody may act, and the table is not idle either.
  property bool dealerPlaying: false

  readonly property var activeHand: hands.length > activeIndex ? hands[activeIndex] : null
  readonly property bool split: hands.length > 1

  readonly property string summary: {
    if (!settled) return ""
    var results = []
    for (var i = 0; i < hands.length; i++) results.push(hands[i].result)
    return Blackjack.handsSummary(results)
  }

  // A natural is the table's own jackpot, so it gets the flourish the slots
  // jackpot gets. It is not the rarest thing in the casino — about one hand in
  // twenty-one against one spin in a hundred and twenty-five — but it is the
  // best thing that can happen here, and that is what a flourish marks.
  readonly property bool natural: {
    for (var i = 0; i < hands.length; i++)
      if (hands[i].result === "blackjack") return true
    return false
  }
  readonly property bool won: {
    for (var i = 0; i < hands.length; i++)
      if (Blackjack.isWin(hands[i].result)) return true
    return false
  }

  // What the bar reports: the best total still standing, or the first hand's
  // if they all busted. `playerCards` used to be a property here and the bar
  // still asked for it after the split refactor turned it into an array of
  // hands — which is why the label read "A" with nothing beside it.
  readonly property int finishedTotal: {
    if (hands.length === 0) return -1
    var best = -1
    for (var i = 0; i < hands.length; i++) {
      var t = Blackjack.handValue(hands[i].cards).total
      if (t <= 21 && t > best) best = t
    }
    return best >= 0 ? best : Blackjack.handValue(hands[0].cards).total
  }

  readonly property bool canHit: inHand && activeHand && !activeHand.frozen
  readonly property bool canDouble: canHit && activeHand.cards.length === 2
  readonly property bool canSplit: canHit && Blackjack.canSplit(activeHand.cards, hands.length)

  // Back to the size they were before splitting arrived. They were shrunk to
  // make room for four hands, and then the fit logic made that unnecessary: a
  // short hand — which is most of them — gets the full size, and a long one
  // scales itself down.
  readonly property int cardWidth: Style.space(42)
  readonly property int cardHeight: Style.space(58)

  implicitHeight: column.implicitHeight

  // The shoe exists before the first card is drawn from it, so the tray is
  // part of the laid table rather than something that appears mid-deal and
  // shoves the panel down a line.
  Component.onCompleted: if (root.shoe.length === 0) root.shoe = Blackjack.newShoe()

  function cardColor(card) {
    if (!card) return Qt.darker(root.foreground, 2.4)
    // A red card is red; a black one is the panel's own ink. Dimming the black
    // ones to "not red" would make half the shoe look face down.
    return card.red ? "#e64343" : root.foreground
  }

  function draw() {
    if (Blackjack.needsShuffle(root.shoe)) root.shoe = Blackjack.newShoe()
    var next = root.shoe.slice()
    var card = next.pop()
    root.shoe = next
    return card
  }

  function newHand(cards, fromSplit) {
    return { cards: cards, doubled: false, done: false,
             fromSplit: !!fromSplit, frozen: false, result: "" }
  }

  function replaceHand(index, hand) {
    var next = root.hands.slice()
    next[index] = hand
    root.hands = next
  }

  function deal() {
    if (root.inHand || root.dealerPlaying) return
    root.settled = false
    root.holeDown = true
    root.hands = [newHand([draw(), draw()], false)]
    root.dealerCards = [draw(), draw()]
    root.activeIndex = 0
    root.inHand = true
    root.requestSound("tick")

    // A natural resolves itself; sitting on the buttons waiting for a HIT that
    // cannot help would be theatre.
    if (Blackjack.isBlackjack(root.hands[0].cards) || Blackjack.isBlackjack(root.dealerCards))
      finish()
  }

  function hit() {
    if (!root.canHit) return
    var hand = root.activeHand
    hand.cards = hand.cards.concat([draw()])
    replaceHand(root.activeIndex, hand)
    root.requestSound("tick")
    if (Blackjack.isBust(hand.cards) || Blackjack.handValue(hand.cards).total === 21) advance()
  }

  function stand() {
    if (!root.canHit) return
    advance()
  }

  // Without stakes a double is not a bet, it is a commitment: exactly one more
  // card and this hand is over. That still changes what you should do, which
  // is the part worth keeping.
  function doubleDown() {
    if (!root.canDouble) return
    var hand = root.activeHand
    hand.doubled = true
    hand.cards = hand.cards.concat([draw()])
    replaceHand(root.activeIndex, hand)
    root.requestSound("tick")
    advance()
  }

  function splitHand() {
    if (!root.canSplit) return
    var hand = root.activeHand
    var aces = Blackjack.isAcePair(hand.cards)

    var first = newHand([hand.cards[0], draw()], true)
    var second = newHand([hand.cards[1], draw()], true)

    // Split aces take one card each and stop. That rule is the whole reason
    // splitting aces is not free money, and it is why A-A that draws two tens
    // is two twenty-ones rather than two blackjacks.
    if (aces) { first.frozen = true; second.frozen = true }

    var next = root.hands.slice()
    next.splice(root.activeIndex, 1, first, second)
    root.hands = next
    root.requestSound("tick")

    if (aces) advance()
  }

  // Moves to the next hand still owed a decision, or ends the round.
  function advance() {
    var hand = root.activeHand
    if (hand) { hand.done = true; replaceHand(root.activeIndex, hand) }

    for (var i = 0; i < root.hands.length; i++) {
      if (!root.hands[i].done && !root.hands[i].frozen) {
        root.activeIndex = i
        return
      }
    }
    finish()
  }

  // The hand is over for the player; the dealer's turn begins.
  function finish() {
    root.holeDown = false
    root.inHand = false

    // The dealer plays only against a hand that still needs beating. A busted
    // hand needs nothing — drawing against a table of busts is a ritual the
    // house performs for the cameras. Nor does a natural: the player has
    // already won it, or pushed against the dealer's own, and whether the
    // dealer could have reached nineteen is not a question the rules ask.
    var needsDealer = false
    for (var i = 0; i < root.hands.length; i++) {
      var h = root.hands[i]
      if (Blackjack.isBust(h.cards)) continue
      if (!h.fromSplit && Blackjack.isBlackjack(h.cards)) continue
      needsDealer = true
    }

    if (!needsDealer) { settleRound(); return }

    root.dealerPlaying = true
    dealerDraw.restart()
  }

  // One card at a time, on a beat. A dealer who lays down four cards in a
  // single frame has not drawn to seventeen, it has simply announced the
  // answer — and the whole tension of a hand you have stood on is watching
  // the total climb toward a bust that may or may not come.
  Timer {
    id: dealerDraw
    interval: 460
    repeat: true
    onTriggered: {
      if (!Blackjack.dealerShouldHit(root.dealerCards)) {
        stop()
        root.dealerPlaying = false
        root.settleRound()
        return
      }
      root.dealerCards = root.dealerCards.concat([root.draw()])
      root.requestSound("tick")
    }
  }

  function settleRound() {
    var next = root.hands.slice()
    var stats = root.stats
    for (var j = 0; j < next.length; j++) {
      next[j].result = Blackjack.settleHand(next[j].cards, root.dealerCards, next[j].fromSplit)
      // Each hand counts as a hand: two split hands are two results, two
      // entries in the tally, and two chances to break a streak. Counting a
      // split as one would quietly make the numbers mean something else.
      stats = Blackjack.recordHand(stats, next[j].result)
    }
    root.hands = next
    root.stats = stats
    root.settled = true
    root.statsUpdated()

    if (root.natural) root.requestSound("jackpot")
    else if (root.won) root.requestSound("win")
  }

  // ---- One row of cards.
  component Hand: Row {
    id: hand
    property var cards: []
    property bool hideSecond: false
    property bool celebrate: false
    property real maxWidth: 0

    // Hands do not have a length limit — an ace-and-twos hand can run to
    // eleven cards, and a table that fits five is a table that eventually
    // draws the sixth off the edge of the panel. So the cards shrink to fit
    // rather than the row overflowing.
    //
    // Shrinking rather than fanning: a real hand is fanned so the corner
    // indices stay visible, and these cards carry their rank in the middle,
    // where an overlap would cover exactly the thing worth reading.
    readonly property real gap: Style.space(5)
    // Scales both ways. It only ever shrank before, which kept long hands on
    // the panel and left a two-card hand sitting in ninety pixels of a
    // three-hundred-and-eighty pixel row — correct, and empty. Growing up to a
    // cap means the table is always as full as the hand allows.
    readonly property real fit: {
      var n = hand.cards.length
      if (n === 0 || hand.maxWidth <= 0) return 1
      var needed = n * root.cardWidth + (n - 1) * hand.gap
      // The ceiling is what stops two cards becoming two billboards — which
      // at 1.8 is exactly what they became. The room is bought back by
      // centring the hand and spreading the line above it; the cards only
      // need to be a little larger than their base, not twice it.
      return Math.max(0.4, Math.min(1.2, hand.maxWidth / needed))
    }

    spacing: Math.round(hand.gap * hand.fit)

    Repeater {
      model: hand.cards

      Rectangle {
        id: card
        required property var modelData
        required property int index

        // A null card is a place at the table rather than a card: before the
        // first deal the felt should look ready, not broken.
        readonly property bool ghost: card.modelData === null
        readonly property bool facedown: !ghost && hand.hideSecond && index === 1

        width: Math.round(root.cardWidth * hand.fit)
        height: Math.round(root.cardHeight * hand.fit)
        // A hit changes how much room each card gets, so the others settle
        // into the new size rather than snapping to it.
        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
        radius: Style.cornerRadius
        color: "transparent"
        border.width: Style.spacing.hairline
        border.color: hand.celebrate && !ghost
          ? Color.accent
          : (ghost || facedown
              ? Style.normalBorderFor(root.foreground, root.foreground)
              : root.cardColor(modelData))

        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: (card.ghost || card.facedown) ? "◇" : Blackjack.rankLabel(card.modelData)
          color: hand.celebrate && !card.ghost
            ? Color.accent
            : ((card.ghost || card.facedown)
                ? Qt.darker(root.foreground, 2.4)
                : root.cardColor(card.modelData))
          font.family: root.fontFamily
          font.pixelSize: Math.max(Style.font.caption, Math.round(Style.font.subtitle * hand.fit))
        }

        // Dealt rather than simply present. Both animations name the card by
        // id: an animation is not a visual item, so `parent` inside one
        // resolves to nothing — write it that way and the opacity never leaves
        // zero and every card deals into thin air.
        // A place at the table is simply there; only a real card is dealt in.
        opacity: ghost ? 0.35 : 0
        transform: Translate { id: lift; y: ghost ? 0 : Style.space(6) }
        Component.onCompleted: { if (!ghost) { dealIn.start(); liftIn.start() } }

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

        // The natural's flourish, the same swell the slots jackpot rolls
        // across its reels, staggered so it travels the hand rather than
        // pulsing it all at once.
        SequentialAnimation {
          id: naturalPulse
          loops: 3
          PauseAnimation { duration: Math.min(card.index, 4) * 90 }
          NumberAnimation {
            target: card; property: "scale"; to: 1.14
            duration: 150; easing.type: Easing.OutQuad
          }
          NumberAnimation {
            target: card; property: "scale"; to: 1.0
            duration: 240; easing.type: Easing.OutBack
          }
          // Clamped: the tail pause is the wave's lead-in run backwards, and
          // on a hand longer than three cards the subtraction goes negative,
          // which an animation refuses once per card per loop.
          PauseAnimation { duration: Math.max(0, (4 - Math.min(card.index, 4))) * 90 }
        }

        Connections {
          target: hand
          function onCelebrateChanged() { if (hand.celebrate) naturalPulse.restart() }
        }
      }
    }
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(12)

    // ---- Dealer.
    //
    // The line sits above the cards rather than beside them. Beside them it
    // shared a row with the hand and had to be cut to fit — which is how
    // DOUBLED became an ellipsis pressed against the first card. Above, the
    // line has the whole panel and so do the cards, and neither has to give
    // the other room.
    Column {
      width: parent.width
      spacing: Style.space(4)

      Item {
        width: parent.width
        height: dealerName.implicitHeight

        Text {
          id: dealerName
          textFormat: Text.PlainText
          anchors.left: parent.left
          text: "DEALER"
          color: Qt.darker(root.foreground, 1.7)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }

        Text {
          textFormat: Text.PlainText
          anchors.right: parent.right
          text: Blackjack.totalLabel(root.dealerCards, root.holeDown)
          color: Qt.darker(root.foreground, 1.7)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }
      }

      // Centred, not left-aligned. Left-aligned was the fix for cards
      // shuffling sideways on every hit, and the sizes animate now, so that
      // movement is a settle rather than a jump — which buys back the
      // composition: two hands on one axis, the way they sit on a table.
      Hand {
        anchors.horizontalCenter: parent.horizontalCenter
        cards: root.dealerCards.length > 0 ? root.dealerCards : [null, null]
        hideSecond: root.holeDown
        maxWidth: parent.width
      }
    }

    // The table's own line. The dealer's side and the player's side are two
    // places at one table, and nothing said so.
    Rectangle {
      width: parent.width
      height: Style.spacing.hairline
      color: root.foreground
      opacity: 0.08
    }

    // ---- The player's hands. One block each, because a split is two hands
    //      and drawing them as one row of six cards is how you lose track of
    //      which cards belong together.
    Repeater {
      model: root.hands

      Column {
        required property var modelData
        required property int index

        readonly property bool isActive: root.inHand && index === root.activeIndex

        width: column.width
        spacing: Style.space(4)

        // A ledger line rather than a label: who on the left, what they hold
        // on the right, and the width between them doing the work instead of
        // sitting empty.
        Item {
          width: parent.width
          height: handName.implicitHeight

          Text {
            id: handName
            textFormat: Text.PlainText
            anchors.left: parent.left
            text: root.split ? ((isActive ? "▸ " : "  ") + "HAND " + (index + 1)) : "YOU"
            color: isActive || !root.split ? root.foreground : Qt.darker(root.foreground, 1.9)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }

          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            text: Blackjack.totalLabel(modelData.cards, false)
              + (modelData.doubled ? "   DOUBLED" : "")
              + (root.settled && root.split ? "   " + Blackjack.outcomeLabel(modelData.result) : "")
            color: root.settled && Blackjack.isWin(modelData.result)
              ? Color.accent
              : (isActive || !root.split ? root.foreground : Qt.darker(root.foreground, 1.9))
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }
        }

        Hand {
          anchors.horizontalCenter: parent.horizontalCenter
          cards: modelData.cards
          celebrate: root.settled && modelData.result === "blackjack"
          maxWidth: parent.width
        }
      }
    }

    // The player's place before the first deal, so the table is laid rather
    // than blank.
    Column {
      width: parent.width
      spacing: Style.space(4)
      visible: root.hands.length === 0

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: "YOU"
        color: Qt.darker(root.foreground, 2.0)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
      }

      Hand {
        anchors.horizontalCenter: parent.horizontalCenter
        cards: [null, null]
        maxWidth: parent.width
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
        // With a split the per-hand labels already say it; this line would
        // only repeat them.
        text: root.split ? " " : (root.summary || " ")
        color: root.won ? Color.accent : Qt.darker(root.foreground, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.letterSpacing: 1

        SequentialAnimation {
          id: naturalWord
          NumberAnimation {
            target: outcomeText; property: "font.letterSpacing"
            from: 1; to: 7; duration: 420; easing.type: Easing.OutCubic
          }
        }
        Connections {
          target: root
          function onNaturalChanged() {
            if (root.natural) naturalWord.restart()
            else outcomeText.font.letterSpacing = 1
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

    // ---- Actions. Only what is legal right now is live.
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
        font.letterSpacing: 2
      }

      MouseArea {
        id: actionMouse
        anchors.fill: parent
        anchors.margins: -Style.space(5)
        hoverEnabled: action.live
        enabled: action.live
        cursorShape: action.live ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: action.triggered()
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(14)

      TableAction {
        label: "DEAL"
        visible: !root.inHand
        live: !root.inHand && !root.dealerPlaying
        onTriggered: root.deal()
      }

      TableAction {
        label: "HIT"
        visible: root.inHand
        live: root.canHit
        onTriggered: root.hit()
      }

      TableAction {
        label: "STAND"
        visible: root.inHand
        live: root.canHit
        onTriggered: root.stand()
      }

      TableAction {
        label: "DOUBLE"
        visible: root.inHand
        live: root.canDouble
        onTriggered: root.doubleDown()
      }

      TableAction {
        label: "SPLIT"
        visible: root.inHand
        live: root.canSplit
        onTriggered: root.splitHand()
      }
    }

    // ---- The rules and the tray, both stated. A table that does not say
    //      which soft-17 rule it runs is hiding two tenths of a percent, and
    //      one that hides how much shoe is left makes a count unusable.
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

    // ---- The shoe, as six decks rather than a bar.
    //
    // A bar needs a legend before it means anything, and the solid one this
    // started as was the heaviest object on a panel built from hairlines. The
    // shoe is literally six decks, so it is drawn as six: they empty right to
    // left, the one being dealt from drains, and the cut card stands where the
    // shuffle comes — a quarter in, which is a deck and a half.
    //
    // This is the number a count is divided by. Without it a running count is
    // eight spare tens and no idea whether that is an edge or nothing.
    Row {
      width: parent.width
      spacing: Style.space(8)
      visible: root.shoe.length > 0

      Text {
        id: shoeLabel
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Blackjack.shoeLabel(root.shoe)
        color: Qt.darker(root.foreground, 2.1)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
      }

      Item {
        id: tray
        anchors.verticalCenter: parent.verticalCenter
        // Measured off the label rather than guessed at. The guess was 96px
        // and "5.9 DECKS LEFT" sets about 98, so the row ran two pixels past
        // the panel — which is all it takes to look broken.
        width: parent.width - parent.spacing - shoeLabel.width
        height: Style.space(9)

        // Not `left`: Item already has one, FINAL, so that `anchors.left:
        // parent.left` can be written — shadowing it makes the whole type fail
        // to load, which is how this managed to take the panel down with it.
        readonly property real remaining: Blackjack.decksLeft(root.shoe)
        readonly property int decks: Blackjack.DECKS
        readonly property real slot: (width - Style.space(3) * (decks - 1)) / decks

        Row {
          anchors.fill: parent
          spacing: Style.space(3)

          Repeater {
            model: tray.decks

            Rectangle {
              required property int index
              width: tray.slot
              height: tray.height
              radius: Style.cornerRadius / 2
              color: "transparent"
              border.width: Style.spacing.hairline
              border.color: Style.normalBorderFor(root.foreground, root.foreground)

              // How much of this particular deck is left, 0..1. The one being
              // dealt from is the only partial mark on the row, which is what
              // makes the drain visible rather than stepped.
              readonly property real filled: Math.max(0, Math.min(1, tray.remaining - index))

              Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * parent.filled
                height: parent.height
                radius: parent.radius
                color: Qt.darker(root.foreground, 1.8)
                Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutQuad } }
              }
            }
          }
        }

        // The cut card. It does not move; the shoe drains down to meet it.
        Rectangle {
          x: tray.width * Blackjack.PENETRATION - width / 2
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(2, Style.spacing.hairline * 2)
          height: parent.height + Style.space(6)
          color: Color.accent
        }
      }
    }
  }
}
