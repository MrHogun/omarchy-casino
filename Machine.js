.pragma library

// The machine's rules, kept out of the view so the odds are something you can
// read rather than infer from animation code.
//
// Five symbols, three reels, every reel independent and uniform — 125 equally
// likely outcomes. Nothing is weighted, nothing is nudged, and there is no
// near-miss logic: a real machine shows you two sevens and a blank far more
// often than chance allows, and that is the one thing this deliberately does
// not copy.
var SYMBOLS = ["◆", "●", "■", "▲", "7"]

// The blank face before the first spin. Hollow, so an untouched machine reads
// as idle rather than as a losing result.
var IDLE = "◇"

function randomSymbol() {
  return SYMBOLS[Math.floor(Math.random() * SYMBOLS.length)]
}

function randomReels() {
  return [randomSymbol(), randomSymbol(), randomSymbol()]
}

// 1 in 125. The only outcome that gets its own word.
function isJackpot(reels) {
  return reels.length === 3
    && reels[0] === "7" && reels[1] === "7" && reels[2] === "7"
}

// 5 in 125, one of which is the jackpot.
function isThree(reels) {
  return reels.length === 3
    && reels[0] === reels[1] && reels[1] === reels[2]
}

// 60 in 125 — near enough half of all spins, which is why it pays nothing and
// is only ever named. Calling this a win would make the machine feel generous
// while taking exactly as much.
function isPair(reels) {
  if (reels.length !== 3) return false
  return !isThree(reels)
    && (reels[0] === reels[1] || reels[1] === reels[2] || reels[0] === reels[2])
}

function outcome(reels) {
  if (isJackpot(reels)) return "jackpot"
  if (isThree(reels)) return "three"
  if (isPair(reels)) return "pair"
  return "none"
}

function outcomeLabel(result) {
  if (result === "jackpot") return "JACKPOT"
  if (result === "three") return "THREE OF A KIND"
  if (result === "pair") return "SO CLOSE"
  return "NOTHING"
}

// Printed under the reels, because a machine that hides its odds is the other
// kind of machine.
function oddsLabel() {
  return "THREE 1:25   ·   SEVENS 1:125"
}

function emptyStats() {
  return { spins: 0, wins: 0, jackpots: 0, streak: 0, worst: 0 }
}

// `streak` counts the spins since the last win, and `worst` remembers the
// longest such run — the honest statistic for a machine like this, and the
// one that is actually fun to watch climb.
function recordSpin(stats, result) {
  var s = stats && stats.spins !== undefined ? stats : emptyStats()
  var won = (result === "three" || result === "jackpot")
  var streak = won ? 0 : (s.streak + 1)
  return {
    spins: s.spins + 1,
    wins: s.wins + (won ? 1 : 0),
    jackpots: s.jackpots + (result === "jackpot" ? 1 : 0),
    streak: streak,
    worst: Math.max(s.worst, streak)
  }
}

function statsLabel(stats) {
  var s = stats && stats.spins !== undefined ? stats : emptyStats()
  if (s.spins === 0) return ""
  var parts = [s.spins + (s.spins === 1 ? " SPIN" : " SPINS")]
  parts.push(s.wins + (s.wins === 1 ? " WIN" : " WINS"))
  if (s.jackpots > 0) parts.push(s.jackpots + (s.jackpots === 1 ? " JACKPOT" : " JACKPOTS"))
  if (s.worst > 0) parts.push("DRIEST " + s.worst)
  return parts.join("   ·   ")
}
