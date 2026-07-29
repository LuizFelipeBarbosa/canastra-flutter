# Canastra

A Flutter version of the Buraco family — **Buraco**, **Canasta**, **Biriba** and
**Rummy** — for web, iOS, Android and macOS. Play against bots, pass a phone
around a table, or join a hosted table over the network.

Forked from [`canastra-thesis`](../canastra-thesis), a Python rules engine built
for reinforcement-learning research. The rules here are a faithful Dart port of
that engine, checked against it rather than reimplemented from memory.

```bash
flutter run -d chrome          # or: -d macos, -d <device>
flutter test                   # engine parity, multiplayer, UI, online
dart run bin/server.dart       # a host for online play
```

## How it fits together

```
lib/
  engine/       pure Dart rules: cards, config, melds, legal moves, turns, scoring
  ai/           bot opponents, playing from the same view a remote player gets
  multiplayer/  authoritative host, redacted views, the transport seam
  game/         the screen's model: latest view + what you can do with a card
  ui/           screens and widgets
bin/server.dart a reference host you can point the app at
```

Four rules profiles, one engine. A variant is a `RulesConfig` tree in
`engine/profiles.dart`, not a code path — which is why Canasta's frozen pile,
red-three trays and rising initial-meld threshold coexist with Buraco's morto
without either knowing about the other.

## The engine is checked, not trusted

A rules engine that is subtly wrong is worse than one that crashes, so the port
is verified against the Python original move by move:

```bash
# from a checkout of the research repo
uv run --project ../canastra-thesis python tool/export_parity_traces.py \
    --out test/data/parity_traces.json
flutter test test/parity_test.dart
```

Each trace records the shuffled deck order, **every step's complete set of legal
action ids**, and the final itemised scores. The Dart engine deals from the same
deck, replays the same actions, and must offer exactly the same moves at every
step. The committed corpus is 42 traces / 6,614 steps across all four profiles
at both table sizes. An off-by-one in a wildcard rule or an anti-stranding guard
shows up as a set difference long before it shows up as a wrong score.

One deliberate divergence: `turn.truncationCap` ends a round that reaches 400
turns. The Python engine leaves truncation to its RL environment, but a game has
to end — with a whole-pile draw rule two players can take the discard pile from
each other forever, so the stock never depletes. Found by bot self-play hanging
on Biriba. Real games do not come close; across 175 bot matches, 2 rounds
reached it.

## Multiplayer

Online play is scaffolded end to end, and the seam is load-bearing today.

**One authority.** `MatchHost` owns the only real game state and speaks
`ClientCommand` / `ServerEvent`. Clients send an action id from the legal list
they were given and re-render whatever comes back; they never compute state, so
a modified client cannot invent a move.

**One transport interface.** The UI talks to a `GameTransport`:

| Implementation       | Host runs       | Used for                    |
|----------------------|-----------------|-----------------------------|
| `LocalTransport`     | in this isolate | single-player               |
| `HotSeatTransport`   | in this isolate | pass-and-play on one device |
| `WebSocketTransport` | on a server     | online                      |

Offline play goes through the same commands and the same redacted view as online
play, so single-player continuously exercises the multiplayer path — a protocol
bug shows up on day one, not on launch day.

**One redaction boundary.** `TableView` is the only shape that crosses the
transport, and it is built by reading exclusively the zones a seat may know.
Other hands, the stock order and the morto contents are unreachable by
construction. Tests assert a seat is never shown another player's cards, is
never told another seat's legal moves, and that the card counts it can see add
up to the full deck. Bots consume `TableView` too, so a bot cannot peek either.

To play across machines:

```bash
dart run bin/server.dart --profile buraco --players 2 --port 8080
# then in the app: Play online -> ws://<host>:8080, same table name
```

`bin/server.dart` is a real host, covered by `test/online_test.dart`, which
starts it on a socket and drives it with two genuine WebSocket clients. It is
in-memory and unauthenticated on purpose: it exists to prove the seam and to
develop against. Shipping online play means adding identity, persistence,
reconnection tokens and rate limiting — none of which touch the game code.

## Design

A Brazilian-modernist card table rather than a casino one: a saturated indigo
ground carrying an Athos Bulcão-style azulejo motif, warm bone cards, and
accents from Hélio Oiticica's palette.

Colour carries rules rather than decorating it. Three accents, each with exactly
one job:

- **pink** — this card is acting as a wild
- **gold** — this canastra is *limpa*, with no wild in it
- **mint** — you may play here

Making a canastra is what a whole round is spent working toward, so it gets
stamped, at an angle, the moment it happens — gold for limpa, pink for suja.

Suit pips are painted, not typed. No bundled font has the suit characters, so a
string containing one renders as a blank box; `SuitPip` draws them, which also
keeps them identical on every platform.

Interaction is one idea: **pick up a card and everywhere it can legally go
lights up.** `MoveIndex` walks the host's legal-move list and works out which
cards each move spends, using the engine's own planners — so the screen can
never offer a move the engine would reject, and never hides one it would allow.
An "All moves" sheet always lists the raw legal actions, because some moves (a
run that spends a wild you would rather keep) are hard to express by tapping,
and a player should never be locked out of a legal play.

## Tests

```bash
flutter test                                   # everything except goldens
flutter test --run-skipped --update-goldens test/golden_test.dart
```

| Suite              | Covers                                                        |
|--------------------|---------------------------------------------------------------|
| `parity_test`      | move-by-move agreement with the Python engine                 |
| `multiplayer_test` | bots finish matches; views leak nothing; protocol round-trips  |
| `online_test`      | two real clients over a real socket against the real server    |
| `ui_test`          | screens lay out from a 320pt phone to desktop                  |
| `golden_test`      | renders screens to PNG for visual review                       |

## Status

Web and macOS builds are verified. Android is scaffolded but unbuilt here — this
machine has no JDK, so `flutter build apk` cannot run; nothing in the code is
Android-specific. iOS is scaffolded and unbuilt.
