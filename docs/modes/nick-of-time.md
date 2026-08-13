# Gametype scope: Nick of Time (darren)

**Basis:** new mode · **Slug:** `nick-of-time` · **Submitted:** 2026-08-13 17:21 UTC

## The pitch

One robber, everyone else is police, ten minutes on the clock. The robber loots shops and steals cars, and only money physically carried back to a hidden safehouse counts. Everyone takes a turn as the robber and the highest stashed total wins.

The comedy is in the near misses, not the arrests. Your car dies at 0% health, catches fire, and blows you across a pavement in front of three squad cars. You take a corner, dive into an unmarked doorway, go instantly invisible, and watch the entire police force scream past with sirens on. You're 750 short of the lead with nine minutes gone and 4,000 in a bag, so you make the worst decision of your life on purpose and everybody in the room watches you do it.

It works at 9pm on a Thursday because a round is ten minutes, the rules fit in one sentence, and the loot counter on screen means the spectators know exactly how badly it's going before the driver does.

## The core loop

Robber: pick a spawn and a vehicle. Drive to a loot location. Choose smash-and-grab (instant alarm, less take) or quiet entry (alarm on a hidden timer). Stand in the zone while the bag fills and the location drains, deciding every second whether to leave with what you've got. Get out, and either run for a safehouse to stash it or push your luck on another site. Every stash raises your wanted level, which puts more police on the map. Repeat until you cash out or the clock kills you.

Cops: you only ever get truthful live position from line of sight. Lose it and the blip freezes and starts drifting along his last heading while the search radius grows, until it goes cold. Get it back using alarms, crash reports, air support, AI patrols and educated guesses about which loot site he'll hit next. Then physically stop the car: burst tyres, ram, PIT. When it dies, taser him on foot.

## Win / lose

Round ends when: the robber is arrested; the robber chooses "call it a day" inside a safehouse; or the 10 minute timer expires.

Scoring: only stashed value counts. Everything on the robber's person at the moment of arrest or timeout is lost. The car you're driving counts toward your on-person total at value × health%, so it bleeds while you're being rammed and is worth nothing once wrecked.

Match: N players, N rounds, each takes one turn as robber. Highest stashed total wins. Cops score nothing directly; their job is to suppress the robber's number, which stays fair because everyone sits the same exam. Tiebreak on time-to-final-stash.

Fairness requirement: loot values, cop spawns, safehouse selection, clock and weather are seeded once per session and reused identically for every round.

## Night one minimum

Three-state detection (hard lock / drifting soft track / cold) driven by one shared LOS raycast. Convenience store looting with drain and alarm timer. Five safehouses with the invisibility dive. Vehicle damage model with forced bail-out and taser foot chase. Speed rubber-banding. Round timer, on-person vs stashed HUD, live delta to leader, rotating scores.

That is a complete game. Everything below makes it a better one.

## The wishlist

Witness-modelled incident reports (crash calls gated on an NPC actually being nearby, rather than firing on every crash). Manually piloted helicopter with the proximity icon. Cosmetic bonus heli with a 20 second all-cops ping, unlocked on a contact-score deficit. Fake wanted stars tied to stashed total. Non-arresting AI patrols that relay the suspect to human cops by proximity. Roadblocks in the endgame while directly pursued. Endgame patrol swarm near remaining loot and burned safehouses. Banks and jewellers as tier 2 and 3 loot. Cars as loot with cash-in. Armoured vans. Safehouse reveal-on-use.

## Framework features

- **Teams:** custom teams
- **Population:** alive
- **Police:** custom
- **Respawn policy:** robber arrest ends the round, no respawn. Cops respawn after ~15s at the nearest road with a replacement vehicle, so wrecking your car costs you the chase but not the round.
- **Clock / weather override:** locked per session and identical across all rounds in a match. Suggest fixed dusk, clear.
- **Round timer:** 10:00 hard cap

**Other framework asks:**

Routing bucket control per player (the safehouse vanish). Per-player culling radius control (SetPlayerCullingRadius) for air units. Server-side entity spawn with guaranteed round-end cleanup, since leaked AI helis and patrol cars across rounds is the most likely persistent bug. Session-scoped score persistence surviving a restart. Server-authoritative position for all detection maths.

## config.lua knobs

```
-- Detection
LOS_TICK_HZ                 = 5
LOS_GRACE_MS                = 1500   -- unbroken loss before dropping to soft track
LOS_FLAGS                   = 23     -- world + vehicles + objects
SOFT_TRACK_DRIFT_DECAY      = 0.85   -- how fast heading confidence dies
SOFT_TRACK_GROWTH_MPS       = 12
SOFT_TRACK_COLD_RADIUS      = 400
HELI_PROXIMITY_ICON_RADIUS  = 250

-- Rubber banding
BAND_START_DISTANCE         = 250    -- boost begins beyond this
BAND_MAX_MULTIPLIER         = 1.25
BAND_POWER_WEIGHT           = 0.7    -- bias toward acceleration over top speed
POLICE_SPEED_FLOOR_PCT      = 0.80   -- stops a robber griefing in a slow vehicle
AI_PATROLS_RUBBER_BANDED    = false

-- Vehicle damage
DAMAGE_STUTTER_THRESHOLD    = 0.10
DAMAGE_STUTTER_MS           = { 200, 400 }
DAMAGE_HITS_TO_FIRE         = 2
FIRE_TO_EXPLOSION_MS        = 6000
RAM_DAMAGE_SPEED_SCALING    = true
COP_VEHICLES_TAKE_DAMAGE    = true

-- Looting
FILL_RATE_BASE              = 1200   -- value per second at full stock
FILL_RATE_DECAY             = 0.6    -- slows as location depletes
ALARM_QUIET_BAND_S          = { 15, 40 }
ALARM_SMASH_DELAY_S         = 0
PUBLIC_VALUE_UPDATE_ON      = "alarm_or_exit"  -- never live, or the map tracks him

-- Safehouses
SAFEHOUSE_POOL              = 10
SAFEHOUSE_PER_ROUND         = 5
SAFEHOUSE_ENTRY_CLEAR_MS    = 1000
SAFEHOUSE_REVEAL_ON_USE     = true

-- Escalation
VALUE_PER_STAR              = 10000
AI_CARS_PER_STAR            = 1
AI_CARS_MAX                 = 6
AI_RELAY_RADIUS             = 120
BONUS_HELI_CONTACT_THRESH   = 0.15   -- team contact score below this unlocks it
BONUS_HELI_PING_S           = 20
BONUS_HELI_USES_PER_ROUND   = 1
ROADBLOCK_START_S           = 420    -- 7:00
ROADBLOCK_REQUIRES_PURSUIT  = true
ROADBLOCK_MAP_WARNING_S     = 5

-- Robber awareness
PRESSURE_RADIUS             = 400
PRESSURE_STATES             = 3
PRESSURE_UPDATE_DELAY_MS    = 1500
PRESSURE_AI_CONTRIBUTION    = 0.33
ROBBER_INFINITE_STAMINA     = true

-- Round
ROUND_LENGTH_S              = 600
SHOW_DELTA_TO_COPS          = true
```

## Locations (verified tags)

_(no verified tags attached)_

## Locations still needed

Safehouse pool (10 needed): unmarked interiors or alleys spread across Los Santos and Blaine County, each with at least one blind approach where a corner can break line of sight within ~30m of the entry zone. This last property is the whole mechanic and won't survive being picked off a map.

Tier 1 loot, night one (aim for 12 to 20): convenience stores with glass frontage, so the robber can see the street while filling. Shell interiors only, no IPL loading.

Tier 2 loot, wishlist: Fleeca branches. Note each needs an IPL name recorded alongside the coordinate.

Tier 3 loot, wishlist: the jeweller and the big bank. Same, IPL names required.

Robber spawn set (3 to 4): spread so no spawn is adjacent to more than two tier 1 sites.

Cop spawn set (3 to 4): spread so the robber's opening 60 seconds isn't decided by geography.

Roadblock chokepoints: highway and bridge nodes with a physical way past. Roadblocks must be avoidable, never walls.

Cover audit, not a tag task: tunnels, underpasses and multi-storey car parks are handled by the LOS raycast for free and need no zones, but the map needs walking to confirm there's usable air cover in each region. The countryside is expected to be thin, that's the intended tradeoff.

## Acceptance criteria

A robber who breaks line of sight behind a building and doubles back is not immediately re-found by the drifting search circle. The circle follows the wrong way. This is the core feeling and if it fails, nothing else matters.
Losing the robber for 30 seconds and then getting him back via an alarm or a witness call happens at least twice in a five round test, without a cop feeling they got him back for free.
No cop car catches the robber on straights alone. Every catch traces back to cornering, a shortcut, a cutoff, or a burst tyre.
A robber can go from full health vehicle to on-foot-and-tasered in a single continuous sequence with no loading, menu, or state confusion.
At least one safehouse dive per session ends with police visibly overshooting the entrance.
A robber in a slow vehicle cannot become unshakeable. Verify the police speed floor.
AI patrols never arrest, never shoot, and never end a round. Verify across a full five star round.
Zero orphaned entities after five consecutive rounds. Check heli and AI patrol counts at round end.
Public loot values never reveal the robber's live position. Rob a location quietly and confirm no cop-visible number changes until the alarm or exit.
Three players complete a full match in under 40 minutes including lobby time.
