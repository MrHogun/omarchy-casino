# Casino

Slots, European roulette and blackjack for the Omarchy bar. Honest odds, printed on both
machines, and nothing staked — you play for the pull, not for a balance.

Built to look like the rest of Omarchy rather than like a casino: no felt, no
gold, no chrome. Quiet cells on the same spacing scale the calendar uses for
its day grid, hairline borders, small caps, and the theme's own accent spent
on the one thing worth colour — whatever just won.

## Use

| | |
|---|---|
| **Left click** | open the panel |
| **Middle click** | spin the table you are on |
| **Space / Return** | spin, while the panel has focus |
| **Esc** | close |

Two tabs switch between the tables, and the panel reopens on the one you left.
The bar label is the last slots spin's three symbols rather than an icon: an
icon says "there is a casino here" once and then says nothing all day.

## Slots

Five symbols, three reels, every reel independent and uniform — 125 equally
likely outcomes.

| Outcome | Chance | |
|---|---|---|
| `7 7 7` | 1 in 125 | **JACKPOT** |
| three of a kind | 5 in 125 | **THREE OF A KIND** |
| two of a kind | 60 in 125 | *so close* — pays nothing, and is only named |
| anything else | 59 in 125 | nothing |

The reels stop one after another (620ms, 980ms, 1400ms). That stagger is the
whole reason a slot machine is watchable — stopping them together resolves the
question all at once, and the third reel is where the suspense lives.

A jackpot gets the only animation in here: a swell that rolls left to right
across the reels and back three times, while the word pushes its letters
apart.

## Roulette

European, single zero. Thirty-seven pockets in the wheel's **real** order —
not 0 to 36 in a line — so the numbers blurring past are the ones the wheel
would actually show, reds and blacks alternating, highs and lows interleaved.

Drawn as a strip rather than a disc. A wheel in a 380px panel gives each
pocket about ten degrees, which is a ring of illegible numbers, and rotating
the text to match only makes it worse. The strip is what every digital table
uses instead: it reads at this width and it decelerates convincingly.

| Bet | Odds | Chance |
|---|---|---|
| Red / Black | 1:1 | 48.6% |
| Odd / Even | 1:1 | 48.6% |
| 1–18 / 19–36 | 1:1 | 48.6% |
| A number, straight up | 35:1 | 2.7% |

Odds are quoted the way a table quotes them. With nothing staked they are not
a payout — they are a statement of how long the odds are, which is the only
honest reason to show a number you cannot spend.

**Zero loses every outside bet.** That single pocket is the entire house edge
on a European wheel, and leaving it out would be the same dishonesty this
project keeps refusing elsewhere. It says `ZERO TAKES IT` when it happens.

## Blackjack

Six decks, dealer stands on soft 17, reshuffled with a quarter of the shoe
left — the way a table does it. Running a shoe to the last card makes the
final hands predictable to anyone keeping track, which is a real edge and one
worth not handing out quietly.

`HIT`, `STAND` and `DOUBLE`. With nothing staked a double is not a bet, it is
a commitment: exactly one more card and the hand is over. That still changes
what you should do, which is the part worth keeping. **No split** — it needs a
second hand, a second set of controls and a second outcome, and it did not
earn that much of a 380px panel.

Cards carry a rank and a colour and no suit. Not because the font is short of
three of them, though it is — because nothing in blackjack depends on a suit.
No payout, no decision, no rule. Drawing one would be decoration pretending to
be information.

A hole card stays down until the hand is over, and the dealer's total is the
up card alone until then. Showing the real total while a card is face down
would be the house telling you what it is holding.

The dealer plays out only a live hand. Drawing to a busted player is a ritual
the house performs for the cameras, not a rule.

## Nothing is nudged

Neither machine has near-miss logic. A real slot machine shows you two sevens
and a blank far more often than chance allows, because that is what keeps a
hand on the lever — and a real wheel is a real wheel, but the software ones
are not always. That is the one thing deliberately not copied here.

It is also why two of a kind pays nothing: calling half of all spins a win
would make the machine feel generous while taking exactly as much.

## Sound

Reels click as they stop. The roulette ball clatters and slows — each tick
stretches the gap to the next by a tenth, which is what deceleration sounds
like; a fixed interval sounds like a metronome bolted to a wheel.

A win is a four-note arpeggio climbing to the octave; a jackpot or a straight
up is a six-note run landing on a held triad. A losing spin gets nothing
beyond its own clicks — a further noise there would be the machine
congratulating you for nothing.

The sounds are generated, not sampled: sine tones with a second harmonic, a
short attack and an exponential tail, written straight to WAV, a few kilobytes
each. They play through `pw-play`, which PipeWire already provides, so this
brings no audio dependency of its own.

The speaker in the header silences all of it.

## What it tracks

Each table keeps its own tally: spins or hands, wins, the rare thing
(jackpots, straight ups, blackjacks), and **driest** — the longest run without
a win. A push is neither a win nor a loss, so a streak carries across it
rather than resetting on a hand that never resolved. That last one
is the honest statistic for machines like these, and the only one that is
actually fun to watch climb.

Stats live in `~/.local/state/omarchy/slots.json` and survive a restart. They
are written there rather than into the widget's `shell.json` entry: they move
on every spin, and rewriting the bar's own config that often to record a toy's
score would be the wrong thing to churn. Writes are atomic.

The `󰦛` in the header resets both tallies, and dims itself when there is
nothing to reset.

## Install

```sh
omarchy plugin add https://github.com/MrHogun/omarchy-slots.git --enable
```

MIT.
