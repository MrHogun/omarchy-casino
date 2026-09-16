# Slots

A slot machine for the Omarchy bar. Three reels, honest odds, and the last
spin left sitting in the bar where you will see it.

Built to look like the rest of Omarchy rather than like a slot machine: no
cabinet, no gold, no chrome. Three quiet cells on the same spacing scale the
calendar uses for its day grid, hairline borders, small caps, and the theme's
own accent spent on the one thing worth colour — the row that just won.

## Use

| | |
|---|---|
| **Left click** | open the machine |
| **Middle click** | spin without stopping to look at it first |
| **Space / Return** | spin, while the panel has focus |
| **Esc** | close |

The bar label is the last spin's three symbols rather than an icon. An icon
would say "there is a slot machine here" once and then say nothing all day;
the result says the same thing and leaves the outcome where you can see it.
A win tints it with the theme accent until the next spin.

## Sound

Each reel clicks as it stops, and a win gets a short rise — a jackpot gets
three notes instead of two. A losing spin gets nothing beyond its three
clicks: giving it a fourth noise would be the machine congratulating you for
nothing.

The speaker in the panel header silences all of it, and the choice is
remembered. It is the only thing this plugin persists.

A win is a four-note arpeggio climbing to the octave; a jackpot is a six-note
run that lands on a held triad. The three sounds are generated, not sampled —
sine tones with a second harmonic, a short attack and an exponential tail,
written straight to WAV. They are a few
kilobytes, they ship with the plugin, and they are played through `pw-play`,
which PipeWire already provides.

## The odds, which are printed on the machine

Five symbols, three reels, every reel independent and uniform — 125 equally
likely outcomes.

| Outcome | Chance | |
|---|---|---|
| `7 7 7` | 1 in 125 | **JACKPOT** |
| three of a kind | 5 in 125 | **THREE OF A KIND** |
| two of a kind | 60 in 125 | *so close* — pays nothing, and is only named |
| anything else | 59 in 125 | nothing |

Nothing is weighted, nothing is nudged, and there is **no near-miss logic**.
A real machine shows you two sevens and a blank far more often than chance
allows, because that is what keeps a hand on the lever. That is the one thing
this deliberately does not copy — which is also why "two of a kind" pays
nothing here. Calling half of all spins a win would make the machine feel
generous while taking exactly as much.

The odds are printed under the reels, because a machine that hides them is
the other kind of machine.

## What it tracks

Spins, wins, jackpots, and **driest** — the longest run of spins without a
win. That last one is the honest statistic for a machine like this, and the
only one that is actually fun to watch climb.

Stats live for as long as the shell does. Nothing is written to disk: a toy
that survives reboots starts to feel like a ledger.

## Install

```sh
omarchy plugin add https://github.com/MrHogun/omarchy-slots.git --enable
```

## Notes on the build

- The reels stop one after another (620ms, 980ms, 1400ms). That stagger is
  the whole reason a slot machine is watchable — stopping them together would
  resolve the question all at once, and the third reel is where the suspense
  lives.
- One timer drives every unlocked reel rather than one timer each. They are
  meant to blur at the same rate, and three independent tickers drift apart
  visibly inside a second.
- The spin blur is opacity, not a shader. A symbol swapped every 60ms already
  reads as motion; dimming it is what stops the eye trying to read each one.
- Symbols are `◆ ● ■ ▲ 7`, all of which JetBrains Mono Nerd Font actually
  has — checked against the font's cmap rather than assumed. `◇` is the idle
  face, hollow, so an untouched machine reads as idle rather than as a loss.
- The header is the shell's own `PanelHero`, the component the tailscale,
  dropbox and agents panels use — icon, title, a meta line and a slot for a
  trailing control, which is where the mute sits. The running tally lives in
  that meta line, so the stats need no row of their own.
- The panel anchors under its widget instead of centring on the bar: it
  belongs to an icon on the right, and a popup opening in the middle of the
  screen loses the thread back to what opened it.

MIT.
