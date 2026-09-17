.pragma library

// European roulette: 37 pockets, one zero. The American wheel's second zero
// exists to double the house edge, and a machine that takes nothing has no
// reason to carry it.
//
// This is the real pocket order, not 0..36 in a line. It matters because the
// strip animates through the wheel as it is actually laid out, so the numbers
// blurring past are the ones you would really see — reds and blacks
// alternating, high and low interleaved.
var WHEEL = [
  0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10,
  5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26
]

var REDS = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]

function colorOf(n) {
  if (n === 0) return "green"
  return REDS.indexOf(n) >= 0 ? "red" : "black"
}

function wheelIndex(n) {
  return WHEEL.indexOf(n)
}

function randomPocket() {
  return WHEEL[Math.floor(Math.random() * WHEEL.length)]
}

// ---- Bets.
//
// The outside bets plus a straight-up number. No columns, dozens, splits or
// corners: they pay the same house edge as everything else here (which is to
// say none), and a betting board that needs 40 targets does not belong in a
// 380px panel.
//
// Odds are quoted the way a table quotes them. With nothing staked they are
// not a payout, they are a statement of how long the odds are — which is the
// only honest reason to show a number you cannot spend.
var BETS = [
  { key: "red",    label: "RED",    odds: "1:1",  chance: 18 / 37 },
  { key: "black",  label: "BLACK",  odds: "1:1",  chance: 18 / 37 },
  { key: "odd",    label: "ODD",    odds: "1:1",  chance: 18 / 37 },
  { key: "even",   label: "EVEN",   odds: "1:1",  chance: 18 / 37 },
  { key: "low",    label: "1–18",   odds: "1:1",  chance: 18 / 37 },
  { key: "high",   label: "19–36",  odds: "1:1",  chance: 18 / 37 },
  { key: "number", label: "NUMBER", odds: "35:1", chance: 1 / 37 }
]

function betFor(key) {
  for (var i = 0; i < BETS.length; i++)
    if (BETS[i].key === key) return BETS[i]
  return null
}

// Zero loses every outside bet. That single pocket is the entire house edge on
// a European wheel, and leaving it out would be the near-miss dishonesty this
// project keeps refusing.
function wins(betKey, number, chosenNumber) {
  if (betKey === "number") return number === chosenNumber
  if (number === 0) return false
  switch (betKey) {
    case "red":   return colorOf(number) === "red"
    case "black": return colorOf(number) === "black"
    case "odd":   return number % 2 === 1
    case "even":  return number % 2 === 0
    case "low":   return number >= 1 && number <= 18
    case "high":  return number >= 19 && number <= 36
  }
  return false
}

function resultLabel(betKey, number, chosenNumber) {
  if (betKey === "number" && number === chosenNumber) return "STRAIGHT UP"
  if (wins(betKey, number, chosenNumber)) return "WON"
  if (number === 0 && betKey !== "number") return "ZERO TAKES IT"
  return "LOST"
}

// ---- The strip.
//
// The wheel written out four times, and the strip rests on the second copy —
// not the first. Resting on the first leaves nothing to the left of the
// marker and half the viewport empty, which is what it looked like before.
// With a lap behind it there is always wheel on both sides.
//
// A spin lands two copies further along, so it travels two full laps plus the
// gap between pockets; on settling the strip is shifted back those two laps,
// which is pixel-for-pixel identical because the copies are, and the next spin
// starts with the same runway. That is what keeps the travel long without the
// strip having to be endless.
var LAPS = 4
var REST_LAP = 1

function strip() {
  var out = []
  for (var i = 0; i < LAPS; i++) out = out.concat(WHEEL)
  return out
}

function stripLandingIndex(number) {
  return WHEEL.length * (REST_LAP + 2) + wheelIndex(number)
}

function stripRestIndex(number) {
  return WHEEL.length * REST_LAP + wheelIndex(number)
}

// How far to pull the strip back once it has settled, in pockets.
function settleShift() {
  return WHEEL.length * 2
}

function lapLength() {
  return WHEEL.length
}

function emptyStats() {
  return { spins: 0, wins: 0, straights: 0, streak: 0, worst: 0 }
}

function recordSpin(stats, won, straight) {
  var s = stats && stats.spins !== undefined ? stats : emptyStats()
  var streak = won ? 0 : (s.streak + 1)
  return {
    spins: s.spins + 1,
    wins: s.wins + (won ? 1 : 0),
    straights: s.straights + (straight ? 1 : 0),
    streak: streak,
    worst: Math.max(s.worst, streak)
  }
}

function statsLabel(stats) {
  var s = stats && stats.spins !== undefined ? stats : emptyStats()
  if (s.spins === 0) return ""
  var parts = [s.spins + (s.spins === 1 ? " SPIN" : " SPINS")]
  parts.push(s.wins + (s.wins === 1 ? " WIN" : " WINS"))
  if (s.worst > 0) parts.push("DRIEST " + s.worst)
  return parts.join(" · ")
}

function straightBadge(stats) {
  var s = stats && stats.straights !== undefined ? stats : emptyStats()
  if (!s.straights) return ""
  return s.straights === 1 ? "1 STRAIGHT" : (s.straights + " STRAIGHTS")
}
