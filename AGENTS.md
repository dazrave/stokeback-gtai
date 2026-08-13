# Agent brief

Read this before implementing any issue. Each issue in this repo is either a
request overheard from the mates playing the game, or one they filed by hand
during the week. Your job is to make the change they'd have wanted — not merely
the change the words literally describe.

Issues are labelled on three axes: a **type** (`new-mode`, `enhance`, `feature`,
`balance`, `bug`, `chore`), a **mode** (`mode:infected`, `mode:pint`,
`mode:chase`, `mode:squadmate`, `mode:nick-of-time`,
`mode:the-stokeback-triathlon`, `mode:meta`), and a
**handling** label. Only pick
up `auto`; leave `needs-human` and `unclear` for a person. `scoped` on a
`new-mode` issue means a human already did the design — the spec lives in
`docs/modes/`, and its decomposed child issues labelled `auto` are fair game.

## What this is

Custom co-op game modes for GTA V / FiveM, played weekly by a growing crew of
mates. It is a comedy, not a serious server. The tone is **Shaun of the Dead**: a pub, an
apocalypse, a getaway van that runs out of petrol at the worst moment. Jokes in
the chat lines are correct and expected.

There are six modes and one companion — read the [README](README.md) for what
each one is before touching it. `the-stokeback-triathlon` is the newest, and
like `nick-of-time` it ships without a single coordinate: both refuse to start
until the tag board has them.

## How to behave

**Take your best swing. Do not ask for clarification.** If a request is
ambiguous, implement it as you honestly read it and ship it. Half the fun for
the players is finding out how the request was interpreted; a literal reading of
a misheard word that becomes a real feature is the point, not a bug. The issue
already contains the verbatim quote and the game state when it was said — that is
your context, use it.

The **only** things you may refuse or downgrade to a human:

- anything that wipes player progress, deletes data, or takes the server down
- anything needing a new **map coordinate** you can't verify (you cannot see the
  map — a guessed coordinate puts cars inside buildings and players in the sky;
  this has happened repeatedly). Relabel those `needs-human` and stop.

**Keep it playable.** A change that crashes the client or breaks a mode mid-session
ruins the evening. When in doubt, make the smaller change.

## Config-first

Every tunable lives in a resource's `config.lua`. The behaviour files avoid
hardcoding numbers. **Most requests are a config edit** — find the number before
you touch logic. The levers:

| If they want to change... | Look in |
|---|---|
| zombie speed / health / archetypes | `infected/client/archetypes.lua` (moveRate, health, sprintAt) |
| horde size, wave growth, difficulty | `infected/config.lua` → `waves`, `budget` |
| where/how far zombies spawn | `infected/config.lua` → `spawn` (minDistance, maxDistance, forwardArc) |
| carjacking / drag-out feel | `infected/config.lua` → `hijack` |
| one-hit-kill, night/fog, ambient city | `infected/config.lua` → `survival` |
| player weapon & ammo in the apocalypse | `infected/config.lua` → `player`; `pint/config.lua` → `player` |
| ammo-carrier ("copper") odds & drop | `infected/config.lua` → `carrier` |
| mission structure, stages, order, story | `pint/config.lua` → `missions` (data only) |
| fuel drain, sputter, refuel rate | `pint/config.lua` → `fuel` |
| revives (time, radius, hold) | `pint/config.lua` → `reviveSeconds/Radius/HoldSeconds` |
| secure-the-area timers & reward | `pint/config.lua` → `secureSeconds`, `secureAmmo` |
| the random events / vignettes | `pint/client/moments.lua`; list in `pint/config.lua` → `moments` |
| which cars the crew get | `pint/config.lua` → `crewCars`, `beaterModels` |
| chase timing, headstart, round length | `chase/config.lua` → top-level seconds |
| line-of-sight tracking & search radius | `chase/config.lua` → `sight`, `search` |
| fugitive lethality, AI police, fleet | `chase/config.lua` → `nonLethal`, `ai`, `cop` |
| squadmate accuracy, health, weapon | `squadmate/config.lua` → `bot` |
| how fast the robber is lost / the search circle drifts | `nick-of-time/config.lua` → `detection` |
| shop takings, alarm timers, smash-vs-quiet trade | `nick-of-time/config.lua` → `looting` |
| the safehouse dive & what banking costs | `nick-of-time/config.lua` → `safehouses` |
| police speed help on a long straight | `nick-of-time/config.lua` → `banding` |
| the getaway car's cough, fire and fireball | `nick-of-time/config.lua` → `damage` |
| stars, alarms-per-stash, roadblocks (unbuilt) | `nick-of-time/config.lua` → `escalation` |
| where the shops, safehouses and spawns are | `nick-of-time/config.lua` → `locations` (tag board only, never guessed) |
| race length, the post-winner window, the countdown | `the-stokeback-triathlon/config.lua` → `round` |
| checkpoint radii, bike/plane models, per-leg feel | `the-stokeback-triathlon/config.lua` → `legs` (one block per discipline) |
| how fussy the wrong-vehicle and on-foot checks are | `the-stokeback-triathlon/config.lua` → `rules` |
| crash recovery: delay, penalty, the airborne restart | `the-stokeback-triathlon/config.lua` → `respawn`, `vehicles` |
| the race course itself (checkpoints, transitions, finish) | `the-stokeback-triathlon/config.lua` → `courses` (tag board only, never guessed) |

A new mission or vignette is **data**: add an entry, don't write a new system.

## The framework

`core` is the foundation every mode sits on. **Never re-implement these** — if
you find yourself writing any of them inside a mode, stop and use core's:

| Need | Use |
|---|---|
| stream a model | `SBM.loadModel(name, timeoutMs?)` |
| drop a ped onto loaded ground | `SBM.settleToGround(expectedZ)` |
| feed ticker / big moment card / HUD text | `SBM.notify` / `SBM.shard` / `SBM.drawText` |
| do something behind a fade | `SBM.behindFade(fn)` |
| remember spawned entities + sweep them | `SBM.tracker()` |
| an AI ped that must not die by accident | `SBM.hardenPed(ped)` |
| what a player spawns holding | `ApplyLoadout(name)`, kits in `core/shared/loadouts.lua` |
| respawn after death (delay/kit/messages) | `TriggerEvent('core:respawnPolicy', {...})` — see `core/client/respawn.lua` |
| stop other modes / restore the world | `exports.core:claimWorld(name)` / `exports.core:releaseWorld()` |
| a whole round's lifecycle (world, teams, clock, police, FF, respawn, timer, the `/name` command) | `exports.core:RegisterGametype(name, descriptor)` — `core/server/gametype.lua` has the descriptor shape; chase is the reference port |
| end the round from a win condition | `exports.core:EndGametype(reason)` — lands in your `OnEnd(reason)` |
| teams | descriptor `teams = 'ffa' \| 'coop' \| {{id,label,colour,loadout,assign},...}`; `exports.core:SetTeam(src,id)` / `GetTeam(src)` / `GetTeamMembers(id)` / `GetTeams()`; clients hear `core:teamChanged` |
| round clock & weather | descriptor `clock = {hour, minute, weather, freeze}` (or the `core:clock` client event) |
| is the player inside a zone | `SBM.inRadius(coords, radius)` |
| named places for a mode | convention: `Config.locations = { name = {x,y,z,h,role='player-spawn'} }` |

A registered gametype declares `population` (`'empty'|'sparse'|'alive'`),
`police` (`'ambient'|'off'|'custom'` — off/custom mute NPC heat; custom means
the mode spawns its own), `friendlyFire` (`'auto'` = cross-team only, or
true/false), `respawn`, `clock`, `roundSeconds`, `minPlayers` and `hooks`
(`OnStart/OnEnd/OnTick/OnPlayerJoin/OnPlayerLeave`, all pcall'd, OnTick ~1Hz).
The framework owns `/name start|stop` — a ported mode must not register its
own duplicate — and restores everything however the round ends, including the
mode's resource stopping. `OnEnd` may return `'hold'` to keep the world claim
through a planned restart; the mode then owns releasing it.

Wiring a mode in: `client_script '@core/client/lib.lua'` first in
client_scripts, `shared_script '@core/shared/loadouts.lua'` if it names a kit,
and `dependency 'core'`. See `chase/fxmanifest.lua` for the shape.

A new game mode is: a config, its rules, its drama. The mechanics above are
already written.

## Ship it

1. Edit the file(s). Match the surrounding style — it is idiomatic and commented;
   write comments that explain *why*, as the existing ones do.
2. Syntax-check everything: `luac -p` each changed `.lua`. A syntax error shows up
   only as a dead resource at runtime.
3. Deploy and hot-reload just the affected resource(s):
   `scripts/deploy.sh infected` (see the script for the ssh/tmux details).
   **Restarting `infected` also stops `pint`, `chase` and `squadmate`** (they
   depend on it) — re-`ensure` them after, or reload them too.
4. Commit with a message that quotes who asked and for what. Push.
5. Announce in game chat if a deploy hook is wired up; otherwise the commit is
   the record.

Prefer to deploy at a **lull** — mission end, round end, between waves — never
mid-holdout, which would wipe the horde or the run.

## Gotchas that have each cost an evening

- **Relationship groups don't sync between clients.** A ped's group is set by
  whoever spawned it; every other machine sees a default. Cross-client checks
  must use entity **decors**, which sync.
- **`TaskEnterVehicle`'s timeout warps the ped in when it expires.** Pass `-1`.
- **A single ground probe after a teleport fails** — the map hasn't streamed in.
  Retry until collision loads, or players spawn in the sky.
- **`CPointRoute` has 40 slots for the whole game.** Every ped on a navmesh task
  holds one; exhausting it hard-crashes the client. Budget pathfinders.
- **FiveM disables player-vs-player damage by default** (`NetworkSetFriendlyFireOption`).
  It must be ON for chase (so tyres pop and players take hits) and OFF everywhere
  else (so mates can't shoot each other).
- **A drunk movement clipset caps the gait** — a "sprinting" zombie in one still
  shuffles. Reset the clipset before speeding one up.
- **Re-issuing a task every tick restarts its animation**, which reads in-game as
  the AI standing still doing nothing.
- **Scripts can't run `ensure`/`start` console commands** (permission denied) —
  use `StartResource`/`StopResource` natives.
- **A client handler only hears server events if it used `RegisterNetEvent`.**
  `AddEventHandler` alone receives local `TriggerEvent`s and silently nothing
  from `TriggerClientEvent` — the event just never arrives, no error.
- **A resource cannot call its own exports.** Inside one resource, share via
  the common script environment (a global table) instead — see `WorldClaim` /
  `Population` in core's server files.
- **`restart` never re-reads a changed `fxmanifest.lua`** — the server keeps
  the script list it scanned at boot, so files added to a manifest silently
  don't load: no error, exports missing. Run `refresh` first (deploy.sh now
  does this for you).

When you hit a new one, add it here. This list is the most valuable file in the
repo.
