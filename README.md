# Stokeback Mountain

Custom co-op game modes for **GTA V / FiveM**, built for a load of mates and a
weekly game night.

The unusual part: **almost all of this was written live, mid-session, by
[Claude Code](https://claude.com/claude-code)** — while a room full of us were
in-game playing it. Someone says "the zombies should drag us out of the car",
and a few minutes later the zombies drag us out of the car. Occasionally they
do something else entirely, which is most of the fun.

Nothing here is a serious roleplay server. It is a pub, an apocalypse, and a
police chase.

---

## The game modes

### 🧟 `infected` — "28 Frags Later"

Wave-based horde survival. One hit and you're gone.

- **Three archetypes** — the *Shambler* (drunk shuffle, slow, relentless), the
  *Runner* (fast, straightforward), and the *Stalker*, which shuffles in like a
  shambler and then breaks into a dead sprint at 25 metres.
- **Brutes** lead every fifth wave: 2,500 HP, headshot-immune, red blip.
- One in twenty infected is a **copper** in LSPD uniform carrying spare
  magazines — visibly different, so you can pick your target in a crowd.
- Zombies **flank**, funnel through doorways behind whichever one worked out the
  route, **jump off roofs**, refuse to use ladders, and **drag you out of a
  moving car**.
- You cannot escape by running: outrun one and it is recycled back into the
  chase out of sight.
- Permanent night and fog while the apocalypse is engaged; the city empties.

### 🍺 `pint` — the campaign

A Shaun of the Dead-shaped story campaign layered on top of the horde. Missions
are pure data, so a new episode is a config entry.

| Episode | Shape | The gist |
|---|---|---|
| **Last Orders** | A→B road trip | The pub ran dry. There's a boat at Del Perro Pier at dawn. Twenty miles of infected in between, and the waves get worse the nearer the city you get. |
| **Departures** | Gather & return | There's a plane at LSIA. There's no fuel in it. Five jerry cans, all guarded, all across the airport. |
| **Water Landing** | Split up & regroup | The plane made it seventy miles. Everyone washes ashore *alone* along Paleto Bay at night and has to walk to the pub. |

Featuring: a **synced fuel system** (every car has a tank, and they cough when
they're low), **jerry cans you carry by hand**, a car each so the drive is a
race, guarded **ammo stashes**, checkpoint objectives you have to *hold*, and a
**down-but-not-dead** revive system where a mate has to stand over you for five
seconds while the horde arrives.

Plus a **moments director**: every minute or so, somebody gets a scripted
disaster near them — a burning plane comes down, a car full of infected piles
into a wall while the driver flees screaming, a bloke sprints at you shouting
for help and then gets back up wrong.

### 🚓 `chase` — "Scrap Run"

One fugitive in a car, everyone else is police. Ten minute rounds.

- **Line-of-sight tracking** — a copper with eyes on you gives the whole force a
  live GPS lock for ten seconds. Break the sightline and it decays to a
  last-known-position dot with a **search radius that grows** the longer you stay
  hidden.
- The helicopter sees twice as far as anyone on the ground. Its whole job is
  keeping eyes on.
- **Crimes get reported** — nick a car out of sight and a "999 call" pings the
  map a few seconds later with the model and the street. Drive badly and
  witnesses phone that in too. Drive *cleanly* and stay invisible.
- **Armed AI units** join the pursuit, sirens up. Losing your tail slows
  reinforcements rather than stopping them.
- Endings: **clean getaway**, **nicked** (stand over them and cuff them), or
  wrapping the bike round a lamppost.

### 💰 `nick-of-time` — one robber, everyone else is the law

Ten minutes. He loots the shops; only what he physically carries through a
safehouse door counts, and everything in the bag when you nick him goes back on
the shelf.

- **Three-state detection.** A copper with eyes on him is the *only* source of
  truth. Lose him and the dot keeps going the way he was last seen going,
  slowing as the guess ages, with the search circle swelling around it —
  so doubling back behind a building sends the whole force the wrong way.
  Let the circle get big enough and it goes **cold**: nothing on the map at all.
- **Smash-and-grab or quiet entry.** Through the glass is faster but the bell
  rings immediately and half the till is in a drawer you're never getting into.
  Quiet is the full stock and an alarm timer you can't see running.
- **The dive.** Get into a safehouse doorway unseen and you genuinely vanish —
  routing bucket, not a hiding animation — while the entire force screams past.
- **The car dies in public.** It coughs at 10% engine health, catches fire after
  two more shunts, and puts you across a pavement six seconds later.
- Endings: **nicked**, **called it a day** inside a safehouse, or the clock.

Ships **without a single coordinate**: `/nick start` tells you exactly which
locations still need tagging on the tag board.

### 🏁 `the-stokeback-triathlon` — run, ride, fly

Somebody organised a triathlon without checking what one is. Everyone starts
together on a line, and the disciplines escalate.

- **Leg 1, on foot** — a checkpoint course through the city, in order, on your
  own two feet. Traffic and pedestrians are left switched on, so the number 19
  bus is part of the obstacle course.
- **Leg 2, motocross** — identical dirt bikes waiting at the transition. You
  *run to them*; nobody is teleported into anything. Hills, dirt and ridges,
  not roads.
- **Leg 3, biplanes** — the same again with aircraft, then a run of aerial
  gates that gets progressively less sensible.
- **Nobody is ever out.** Die, sink a bike, write off a plane: you go back to
  your last checkpoint with a replacement, and a pilot who has already cleared
  a gate is put back in the air with the engine running rather than on a
  hilltop.
- First over the line wins, and everyone else gets **60 seconds** to finish
  before a DNF. Nobody finishing at all is scored on how far they got.

Ships **without a single coordinate**: `/tri start` reads out exactly what
still needs tagging on the tag board.

### 🤖 `squadmate` — your AI mate

One AI companion each. Follow, hold, be aggressive, copy your weapon, or fetch a
jerry can. He gets in the car with you — but if you drive off without him,
**he's left behind**, and he's a mediocre shot at the best of times.

---

## Commands

Type them in chat with a `/`, or in the F8 console without one.

### Playing

```
/pint start [lastorders|departures|waterlanding]   the campaign (default: lastorders)
/pint stop | skip | list                           abandon / skip a stage / list missions
/horde start | stop | reset                        sandbox wave survival
/wave [n]                                           force the next wave, or jump to wave n
/chase start | stop                                 one fugitive, everyone else is police
/nick start | stop                                  Nick of Time: rob the shops, stash it, get out
/tri start | stop                                   the Stokeback Triathlon: run, ride, fly
/score                                              horde kill leaderboard
/resetgame                                          stop everything, respawn everyone somewhere random, together
```

### Keys

| Key | Does |
|---|---|
| `F6` / `F7` / `F9` | Squadmate: follow / be aggressive / hold position |
| `F10` | Squadmate: respawn him |
| `F11` | Squadmate: copy the weapon you're holding |
| `G` | Squadmate: fetch the nearest jerry can |
| `E` | Interact — pick up / pour jerry cans, loot ammo, arrest (in chase) |
| `G` | Triathlon: my bike/plane is a smoking hole, send another |

### Extras

```
/moment [name]     trigger a random event on yourself (planecrash, crashcar, runner,
                   helicopter, turning, ambulance, faller, stampede, tanker)
/tmark <note>      flag a moment in the telemetry log ("that bridge chase was great")
```

### Dev tools

Live in `infected_dev`, which is **stopped for game night** so nobody has god mode.
When it's running: `/god`, `/noclip` (F2), `/perf` (F4), `/dbg` zombie labels (F3),
`/guns`, `/here`, `/slow`, `/stress`, `/clipset`, `/tp`, plus `/zdbg` (zombie pursuit
debug, lives in `infected`).

---

## Layout

```
resources/[local]/
├── infected/      the horde: spawning, behaviour, waves, carjacking
├── pint/          the campaign: missions, fuel, moments, revives
├── chase/         cops and robbers: sight tracking, AI police, reports
├── nick-of-time/  the heist: loot drain, alarms, the drifting search circle
├── the-stokeback-triathlon/  the race: checkpoints, transitions, biplanes
├── squadmate/     the AI companion
├── infected_dev/  dev tools (god, noclip, wave control) — off for game night
└── telemetry/     route recording, player list, /resetgame
```

Each resource is config-first: `config.lua` holds every tunable, and the
behaviour files avoid hardcoding numbers.

New modes don't hand-roll the plumbing either: a mode registers a **gametype
descriptor** with core (`exports.core:RegisterGametype`) declaring its teams,
population, police, clock, friendly-fire and respawn rules — and core runs the
lifecycle for it: the `/mode start|stop` command, dealing the teams, the round
timer, and putting the whole world back afterwards, however the round ends.
`chase` is the reference port.

## Running it

Requires a [FiveM server](https://docs.fivem.net/docs/server-manual/setting-up-a-server/)
with `cfx-server-data`. Drop `resources/[local]/*` into your server's resources
folder and use the included `server.cfg` as a starting point.

Your FiveM licence key goes in `secrets.cfg` (git-ignored, `exec`'d from
`server.cfg`) — never in the repo.

```bash
scripts/deploy.sh infected pint     # push + hot-reload named resources
```

## Notable things learned the hard way

A running list, because most of these cost an evening:

- **Relationship groups don't sync between clients.** A ped's group is set by
  whoever spawned it; every other machine sees a default. Any cross-client check
  has to use entity **decors**, which do sync. This one silently broke the
  carjacking for days.
- **`TaskEnterVehicle`'s timeout warps the ped in when it expires.** Pass `-1`
  or your AI teleports into the car instead of running to it.
- **A single ground probe after a teleport fails**, because the map hasn't
  streamed in yet — and leaves the player standing in the sky. Retry until
  collision loads.
- **`CPointRoute` has forty slots for the entire game.** Every ped on a navmesh
  task holds one, and exhausting it hard-crashes the client. Budget them.
- **FiveM disables player-vs-player damage by default.** Without
  `NetworkSetFriendlyFireOption`, bullets pass through players *and* their
  vehicles, so nothing takes damage and nothing makes sense.
- **A drunk movement clipset caps the gait**, so a "sprinting" zombie in one
  will still shuffle.
- **Re-issuing a task every tick restarts its animation**, which reads in-game
  as the AI standing still doing nothing.

## Licence

MIT — see [LICENSE](LICENSE).
