.pragma library

// Blackjack, six decks, dealer stands on soft 17.
//
// Cards carry a rank and a colour and no suit. Not because the font is short
// of three of them — though it is — but because a suit changes nothing in this
// game: no payout, no decision, no rule anywhere depends on it. Drawing one
// would be decoration pretending to be information, which is the thing this
// panel keeps not doing.
var RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]

var DECKS = 6
// Reshuffled with a quarter of the shoe left, the way a table does it. Running
// it to the last card would make the final hands predictable to anyone keeping
// track — which is a real edge, and one worth not handing out silently.
var PENETRATION = 0.25

function newShoe() {
  var shoe = []
  for (var d = 0; d < DECKS; d++)
    for (var suit = 0; suit < 4; suit++)
      for (var r = 0; r < RANKS.length; r++)
        // Suits 1 and 2 are the red ones; that is all a suit is used for here.
        shoe.push({ rank: r, red: suit === 1 || suit === 2 })

  // Fisher–Yates. The naive sort-by-random shuffle is biased and this is not
  // the place to be casual about it.
  for (var i = shoe.length - 1; i > 0; i--) {
    var j = Math.floor(Math.random() * (i + 1))
    var t = shoe[i]; shoe[i] = shoe[j]; shoe[j] = t
  }
  return shoe
}

function needsShuffle(shoe) {
  return !shoe || shoe.length < DECKS * 52 * PENETRATION
}

function rankLabel(card) {
  return card ? RANKS[card.rank] : ""
}

function cardValue(card) {
  if (card.rank === 0) return 11          // ace, counted high and pulled back
  if (card.rank >= 9) return 10           // 10, J, Q, K
  return card.rank + 1
}

// Returns the best total the hand can hold, and whether an ace is still being
// counted as eleven — which is what makes a 17 a soft 17.
function handValue(cards) {
  var total = 0
  var aces = 0
  for (var i = 0; i < cards.length; i++) {
    total += cardValue(cards[i])
    if (cards[i].rank === 0) aces++
  }
  while (total > 21 && aces > 0) { total -= 10; aces-- }
  return { total: total, soft: aces > 0 }
}

function isBlackjack(cards) {
  return cards.length === 2 && handValue(cards).total === 21
}

function isBust(cards) {
  return handValue(cards).total > 21
}

// Stands on soft 17. It is the player-friendlier of the two house rules and
// the one worth printing on the machine, since the other costs you about two
// tenths of a percent and nobody ever says which they are running.
function dealerShouldHit(cards) {
  var v = handValue(cards)
  return v.total < 17
}

// ---- Splitting.
//
// Any two cards of equal *value* split, so a K and a Q may be parted the way
// most tables allow — though splitting twenty is a way of turning a winning
// hand into two mediocre ones, and the table will let you do it.
//
// Up to four hands, which is the usual limit, and split aces take exactly one
// card each and stop. That last rule is what stops aces being the free money
// they would otherwise be, and it is why A-A split into two hands drawing a
// ten each is two twenty-ones and not two blackjacks.
var MAX_HANDS = 4

function canSplit(cards, handCount) {
  if (!cards || cards.length !== 2) return false
  if (handCount >= MAX_HANDS) return false
  return cardValue(cards[0]) === cardValue(cards[1])
}

function isAcePair(cards) {
  return cards && cards.length === 2 && cards[0].rank === 0 && cards[1].rank === 0
}

// A hand that came out of a split can reach 21, but never blackjack: a
// blackjack is a two-card 21 dealt to you, and one of those two was chosen.
function settleHand(playerCards, dealerCards, fromSplit) {
  var player = handValue(playerCards).total
  var dealer = handValue(dealerCards).total
  var playerBj = !fromSplit && isBlackjack(playerCards)
  var dealerBj = isBlackjack(dealerCards)

  if (playerBj && dealerBj) return "push"
  if (playerBj) return "blackjack"
  if (player > 21) return "bust"
  if (dealerBj) return "lose"
  if (dealer > 21) return "win"
  if (player > dealer) return "win"
  if (player < dealer) return "lose"
  return "push"
}

function settle(playerCards, dealerCards) {
  var player = handValue(playerCards).total
  var dealer = handValue(dealerCards).total
  var playerBj = isBlackjack(playerCards)
  var dealerBj = isBlackjack(dealerCards)

  if (playerBj && dealerBj) return "push"
  if (playerBj) return "blackjack"
  if (dealerBj) return "lose"
  if (player > 21) return "bust"
  if (dealer > 21) return "win"
  if (player > dealer) return "win"
  if (player < dealer) return "lose"
  return "push"
}

function outcomeLabel(result) {
  if (result === "blackjack") return "BLACKJACK"
  if (result === "win") return "WON"
  if (result === "push") return "PUSH"
  if (result === "bust") return "BUST"
  if (result === "lose") return "LOST"
  return ""
}

function isWin(result) {
  return result === "win" || result === "blackjack"
}

function totalLabel(cards, hideSecond) {
  if (!cards || cards.length === 0) return ""
  if (hideSecond) {
    // While the hole card is down, only the up card is known — showing the
    // real total would be the house telling you what it is holding.
    var v = handValue([cards[0]])
    return String(v.total)
  }
  var h = handValue(cards)
  if (h.total > 21) return h.total + " BUST"
  // "Soft" names a total that can still take a card without busting, which
  // twenty-one cannot. Nobody at a table has ever called one a soft 21.
  if (h.total === 21) return "21"
  return h.soft ? ("SOFT " + h.total) : String(h.total)
}

// Printed under the table, the way the odds are on the other two machines.
function rulesLabel() {
  return "6 DECKS · DEALER STANDS SOFT 17 · 3:2"
}

// What a discard tray tells you at a real table, in the one number that
// matters for it: how much shoe is left. A running count is worth nothing
// without it — eight spare tens across two remaining decks is a real edge and
// the same eight across five is nearly none, which is why counters divide by
// exactly this.
// How much of the shoe is still to come, 0..1 — the tray drawn from it.
function shoeRemaining(shoe) {
  if (!shoe) return 0
  return Math.max(0, Math.min(1, shoe.length / (DECKS * 52)))
}

// How many decks are still to come, as a real number — 6.0 down to 1.5.
function decksLeft(shoe) {
  if (!shoe) return 0
  return shoe.length / 52
}

// The deck the cut card sits in: reshuffle comes at a quarter of the shoe.
function cutAtDecks() {
  return DECKS * PENETRATION
}

function shoeLabel(shoe) {
  if (!shoe || shoe.length === 0) return ""
  var decks = shoe.length / 52
  return (Math.round(decks * 10) / 10).toFixed(1) + " DECKS LEFT"
}

// One line for a hand, several joined for a split.
function handsSummary(results) {
  if (!results || results.length === 0) return ""
  if (results.length === 1) return outcomeLabel(results[0])
  var out = []
  for (var i = 0; i < results.length; i++) out.push(outcomeLabel(results[i]))
  return out.join(" · ")
}

function emptyStats() {
  return { hands: 0, wins: 0, pushes: 0, blackjacks: 0, streak: 0, worst: 0 }
}

// A push is neither, so it breaks nothing and counts as nothing — the streak
// carries across it rather than resetting on a hand that never resolved.
function recordHand(stats, result) {
  var s = stats && stats.hands !== undefined ? stats : emptyStats()
  if (result === "push") {
    return {
      hands: s.hands + 1, wins: s.wins, pushes: s.pushes + 1,
      blackjacks: s.blackjacks, streak: s.streak, worst: s.worst
    }
  }
  var won = isWin(result)
  var streak = won ? 0 : (s.streak + 1)
  return {
    hands: s.hands + 1,
    wins: s.wins + (won ? 1 : 0),
    pushes: s.pushes,
    blackjacks: s.blackjacks + (result === "blackjack" ? 1 : 0),
    streak: streak,
    worst: Math.max(s.worst, streak)
  }
}

function statsLabel(stats) {
  var s = stats && stats.hands !== undefined ? stats : emptyStats()
  if (s.hands === 0) return ""
  var parts = [s.hands + (s.hands === 1 ? " HAND" : " HANDS")]
  parts.push(s.wins + (s.wins === 1 ? " WIN" : " WINS"))
  if (s.pushes > 0) parts.push(s.pushes + " PUSH")
  if (s.worst > 0) parts.push("DRIEST " + s.worst)
  return parts.join(" · ")
}

function blackjackBadge(stats) {
  var s = stats && stats.blackjacks !== undefined ? stats : emptyStats()
  if (!s.blackjacks) return ""
  return s.blackjacks === 1 ? "1 BLACKJACK" : (s.blackjacks + " BLACKJACKS")
}
