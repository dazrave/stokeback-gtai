# Nick of Time — Development Plan

FiveM gametype. One robber vs everyone else, 10 minutes, rotating turns, only stashed loot counts.

---

## 1. Design pillars

Every future decision gets tested against these four. If a feature fails one, it's cut or reworked.

1. **One detection rule.** Cops only ever get truthful live position from line of sight. Everything else — heli icons, safehouse entry, AI relay — derives from the same raycast boolean. No special cases.
2. **Information degrades, it never switches off.** Losing the robber moves cops to a drifting, growing search area, not to nothing. Getting him back is earned through alarms, witnesses, air support and prediction.
3. **AI never wins the game.** AI patrols, helis and roadblocks exist purely to generate information and pressure for human players. They can never arrest, never kill, never end a round. Player vs player is the entire point.
4. **Greed is the game.** The robber's exit is always available and always costs the next score. Escalation (stars, patrols, roadblocks) is brought on by the robber's own success.

---

## 2. Round and match structure

- **Round:** 10:00 hard cap. Ends on arrest, on the robber choosing "call it a day" in a safehouse, or on the clock.
- **Match:** N players, N rounds, each player takes one turn as robber. Only the robber scores; the score is stashed value. Cops suppress, they don't score. Tiebreak: time to final stash.
- **Fairness:** loot values, spawn sets, safehouse selection, clock and weather are seeded once per session and identical across all rounds. Randomise between sessions only.
- **Known quirk:** the last robber knows the target to beat. Accept as a party-game quirk for now; the fix (full set per turn order — N sets of N rounds) exists if it grates.
- **Spawns:** robber picks one of 3–4 spawn locations, each with a vehicle selection. Cops the same, positioned so no opening 60 seconds is decided by geography.
- **Clock/weather:** fixed dusk, clear, locked per session.

---

## 3. Detection model (the core system)

### 3.1 States

| State | Trigger | Cops see |
|---|---|---|
| **Hard lock** | Any cop (ground or heli) has LOS, or bonus-heli ping active | Live updating blip |
| **Soft track** | LOS broken continuously for 1.5s | Drifting search circle + breadcrumb arrow + dispatch text |
| **Cold** | Circle exceeds ~400m radius | Nothing until new intel |

### 3.2 LOS implementation

- Server shortlists candidate cop/robber pairs by distance; relevant client runs the shapetest; server sanity-checks the result against last known positions before granting hard lock.
- Raycast at 5Hz. Flags: world + vehicles + objects. Target the robber's **vehicle** when mounted (the ped raycast counts his own roof as an occluder).
- 1.5s continuous-loss grace before dropping to soft track, so passing lorries don't strobe the blip.
- Tunnels, underpasses, car parks and interiors all block LOS via geometry for free — **no hand-authored occlusion zones needed**.

### 3.3 Soft track

- On LOS break: capture position, heading, speed. Circle centre drifts along last heading at last speed while radius grows.
- Drift confidence decays (~0.85 factor) while growth accelerates; by ~30s it's a non-directional blob centred near the sighting. Handles double-backs without feeling cheated.
- Alongside: a static breadcrumb arrow at the last sighting showing heading, and dispatch text ("Last seen westbound, 95mph, 12s ago").
- Server-authoritative maths; `AddBlipForRadius` + `SetBlipCoords`/`SetBlipScale` on a tick. Road-network reachability propagation is a v2 upgrade.

### 3.4 Witness-modelled incidents (wishlist)

- Crashes, red lights, pedestrian hits fire a call only if an NPC/non-participant is within a visibility radius. Empty docks at 3am = silence; Vespucci Beach = instant call.
- 5–15s delay before the call lands; reports a **point**, not a direction. Two sequential calls let cops derive a bearing themselves — skill, not handout.
- Requires **alive** population; this system is why empty streets are banned.

---

## 4. Robber systems

### 4.1 Looting

- **Drain model:** standing in the zone fills the bag and drains the location. Fill rate decays as stock depletes (fast display cases, slow safes), giving a natural walk-away point.
- **Alarm:** its own randomised timer starting at first fill. Smash-and-grab = instant. Quiet entry = trips somewhere in a hidden 15–40s band. Every extra second is a live gamble.
- Aborting is instant and lossless — you keep what's bagged.
- **Public values never update live.** Displayed value changes only on alarm or exit, or quiet entry is pointless and the map tracks him.
- Alarm sounding = location pinned on all police maps.

### 4.2 Loot tiers (GTA's architecture does the balancing)

| Tier | Locations | Setup | Value | Visibility out |
|---|---|---|---|---|
| 1 (night one) | ~12–20 convenience stores (24/7, LTD, liquor) | Shell interiors, zero IPL work | Low, fast fill | Glass frontage — can watch the street |
| 2 (wishlist) | 6 Fleeca branches | `RequestIpl` + config each | Mid, slower | Blind inside |
| 3 (wishlist) | Vangelico, Pacific Standard | Most setup | Top | Blind inside |
| Exterior (wishlist) | ATMs, armoured vans | None | Varies | Fully exposed in the street |

Blindness in the expensive interiors **is** the risk curve. Warning comes from spatialised sirens, which also gives cops a real choice: sirens = faster through traffic but announced; silent = slower but might catch him mid-fill.

### 4.3 Cars as loot

- Exotics can be driven to a safehouse and cashed in. Value = base × health%, so ramming him bleeds the payout and a wrecked loot car is worth nothing.
- Exotics carry a higher witness-call chance. Taking one means abandoning your current vehicle and its state.
- Safehouse menu: deposit bag / cash in car / back to the streets / call it a day.

### 4.4 Safehouses

- Pool of 10, 5 active per round, **hidden from cops by default**.
- **Reveal-on-use:** depositing reveals that safehouse to all cops for the rest of the round. Forces rotation, builds cop chokepoint knowledge, escalates the endgame naturally.
- **The vanish:** entry requires ~1s of no cop having LOS (same raycast). On entry the player moves to their own routing bucket (`SetPlayerRoutingBucket`) — gone from every client, server-authoritative, no rendering hacks. Vehicle handled in the same move.
- Blocked entry shows a loud "SPOTTED" rejection.
- Entering immediately forces the menu; the only exits are back to the streets or ending the round — no loitering out the clock.

### 4.5 Robber information

- **No cop minimap.** Getting cut off blind is the comedy.
- **Pressure meter:** 3 coarse states (Clear / Nearby / Close), 1.5–2s update delay, driven by cop **density** within ~400m rather than nearest-cop distance — structurally can't telegraph one cop's approach. AI contribution capped at ~1/3 of the bar so 5 stars doesn't peg it.
- Spatialised sirens remain audible, including from inside interiors.
- Infinite sprint stamina; cops normal. Robber carries no weapon; jacking a passing car mid-foot-chase is the comeback play.

### 4.6 Loot HUD

- Two numbers: **ON YOU** (volatile styling) and **STASHED** (safe styling).
- Current vehicle contributes value × health% to ON YOU — leaps when you enter a stolen exotic, craters when you step out, bleeds while being rammed. Bag itself is damage-immune.
- **Delta display**, shown to robber **and cops**:
  - `STASHED −750` (gap to leader)
  - `IF YOU BANK +4,250` (what the next safehouse run is worth)

---

## 5. Cop systems

### 5.1 Rubber banding

- Server computes each cop's distance to robber, broadcasts a band factor; each client applies it to its own vehicle.
- Far behind: boost via engine power/torque multipliers (weight 0.7 toward power — catch-up happens out of corners, not on straights). Within ~250m: capped to the robber's vehicle speed (`SetVehicleMaxSpeed`).
- **Police speed floor at 80% of baseline** so a robber in a bin lorry can't drag everyone to walking pace.
- Helis exempt, default speed. AI patrols **never** rubber-banded.
- Cop vehicle choice differentiates on handling, braking, mass, off-road — not speed.

### 5.2 Vehicle damage and capture (non-lethal by construction)

- Script-owned 0–100 vehicle health; clamp `SetVehiclePetrolTankHealth` high so GTA can't self-ignite.
- 10%: random 200–400ms engine stutters. 0%: cut out, undriveable. +2 hits after that: fire (`StartEntityFire`), explosion on ~6s timer. **Robber is explosion-proof** — the blast throws him clear, which is both the safety requirement and the joke.
- Peds bulletproof, `SetPedCanBeShotInVehicle` false — guns become tyre tools by construction. Burst tyres still drive, badly.
- Damage comes from the robber's own crashes as well as rams (a crash damages you *and* may generate a witness call). **Cop cars take damage too** — ramming has a cost.
- **Jack, never enter:** on keypress in range with the target vehicle near-stationary, `TaskLeaveVehicle` (jacked flag) on the robber + paired jack animations on both peds. The cop is never given an enter task, so he can never end up in the seat.
- On foot, cops carry **tasers only** (weapon-swapped on vehicle exit/entry). Taser ragdoll = the arrest window.
- Escalation ladder: burst/ram → degrade → stop → pull out → foot chase → tase → arrest.

### 5.3 Air support

- **Manual heli:** same LOS rule as ground. Proximity bonus: within ~250m, a large icon renders above the robber for heli occupants only, driven off the same raycast boolean (icon and map can never disagree). Bridges/tunnels break both at once.
- **Bonus heli:** cosmetic AI heli (`TaskHeliMission` follow, high min altitude) spawns above the robber; all cops get a live ping for 20s, then it leaves and the ping dies. Ping is **unconditional** (ignores cover) — it's a rare lifeline and must deliver.
- Unlock on **contact score**, not wall clock: team-wide (hard-lock time + time within 150m) below threshold → button lights. One use per round, team-wide.
- Rubber band answers a *distance* deficit; bonus heli answers an *information* deficit. They must not both fire on the same problem.
- Requires raised `SetPlayerCullingRadius` for airborne players (OneSync culling otherwise makes distant players not exist client-side).

### 5.4 Escalation (fake stars + AI patrols)

- `SetFakeWantedLevel` for display; `SetCreateRandomCops(false)` + dispatch services disabled so nothing stock ever spawns.
- 1 star per £10,000 **stashed**. Each star adds one AI patrol car, capped at 6.
- AI patrols: own spawned peds, neutral relationship group, no weapons, `SetBlockingOfNonTemporaryEvents`, follow-task only. **They relay by proximity (~120m), no LOS check** — while near the suspect, he appears on human cops' minimaps. They can never arrest.
- Not rubber-banded → a well-driven robber genuinely outruns them → they make *areas* dangerous rather than making him permanently tracked.

### 5.5 Endgame pressure

- From ~7:00, **while directly pursued only** (never leaks position otherwise): roadblocks spawn ahead of his projected path via the vehicle node graph, always with a way past, shown on the map ~5s out. A decision, not a gotcha.
- From ~8:00, if he's cold: patrol density shifts to remaining loot sites and **revealed safehouse approaches**.

### 5.6 Auto-GPS

- `SetBlipRoute` to the top-priority target: 1) hard lock 2) sounding alarm 3) witness call <15s old 4) soft-track centre 5) nearest unhit high-value site.
- Hysteresis so it doesn't flip between near-equal targets; manual waypoint suppresses auto-routing for 20s.
- v2: if another cop holds hard lock, route distant units to an intercept point ahead of the robber.

---

## 6. Technical architecture

- **Server-authoritative:** all positions for detection maths, soft-track state, scores, loot/stash ledger, round state machine, seeds, entity spawning.
- **Client:** raycasts (server-requested, server-verified), band factor application to own vehicle, HUD, proximity icon, pressure meter rendering.
- **Routing buckets** for the vanish.
- **Entity lifecycle:** every spawned entity (bonus heli, patrols, roadblocks) registered with the round; cleanup on both its own timer **and** the round-end handler. Leaked entities across rounds is the most likely persistent bug — see acceptance test 8.
- **Persistence:** session score table server-side; JSON/MySQL if it should survive restarts.
- **Anti-cheat posture:** detection is unspoofable because position is server-side and client raycast results are sanity-checked.

---

## 7. Build order

**Phase 1 — the chase is fun with zero content.**
LOS raycast pipeline, three detection states, drifting soft track, rubber banding, round timer, spawns. *Exit test: two people chase each other for 10 minutes and losing/refinding someone already feels good.* If this phase isn't fun, nothing downstream saves it.

**Phase 2 — the loop.**
Tier 1 looting (drain + alarm timers), 5 safehouses with the vanish, ON YOU/STASHED HUD, deposit/call-it-a-day menu, scoring + rotation + delta.

**Phase 3 — the catch.**
Vehicle damage model, forced bail, tyre-only guns, jack-out, taser foot chase, cop respawn (~15s, nearest road, fresh vehicle).

**Phase 4 — escalation (wishlist begins).**
Fake stars, AI patrols + relay, contact score + bonus heli, witness incident calls, pressure meter.

**Phase 5 — endgame + content.**
Roadblocks, endgame patrol shift, auto-GPS, tier 2/3 interiors, cars-as-loot, armoured vans, safehouse reveal-on-use polish.

Phases 1–3 = night one. 4–5 = the wishlist, in value order.

---

## 8. Location work (tag board, no guessed coordinates)

- **10 safehouses** — each needs a blind approach where a corner breaks LOS within ~30m of the entry zone. This property *is* the mechanic; walk each one.
- **12–20 tier 1 stores** with glass frontage.
- **6 Fleeca + jeweller + big bank** (wishlist) — record IPL names with coordinates.
- **3–4 robber spawns** (none adjacent to more than two tier 1 sites), **3–4 cop spawns**.
- **Roadblock chokepoints** — highway/bridge nodes with a physical way past.
- **Air-cover audit** per region (no zones needed, just confirmation the countryside tradeoff plays as intended).

---

## 9. Config knobs

The full `config.lua` block from the scope submission stands as drafted (detection tick/grace/flags, drift decay, band distances and floor, damage thresholds, fill rates and alarm bands, safehouse counts, stars/patrol caps, contact threshold, roadblock timings, pressure meter, round length). Treat every value as a first guess; the tuning sessions below exist to move them.

---

## 10. Acceptance criteria

1. A robber who breaks LOS and doubles back is **not** immediately re-found — the circle follows the wrong way. Core feeling; if this fails nothing else matters.
2. Lose-for-30s-then-refind-via-intel happens ≥2× across five test rounds, without feeling free.
3. No catch from straight-line speed alone — every catch traces to cornering, a shortcut, a cutoff or a burst tyre.
4. Full-health vehicle → on-foot-and-tasered in one continuous sequence, no state confusion.
5. ≥1 safehouse dive per session ends with police visibly overshooting.
6. A slow-vehicle robber cannot become unshakeable (verify the speed floor).
7. AI never arrests, shoots, or ends a round, across a full 5-star round.
8. Zero orphaned entities after five consecutive rounds.
9. Public loot values never reveal live position (quiet-rob a site; confirm no cop-visible change until alarm/exit).
10. Three players finish a full match in under 40 minutes including lobby.

---

## 11. Risks

| Risk | Mitigation |
|---|---|
| Phase 1 chase isn't fun | It's built first, alone, precisely so it can be tuned or killed cheaply |
| OneSync culling breaks heli LOS | Raised culling radius for air units; keep air rare and short-lived |
| Escalation over-tracks the robber at 5 stars | AI cap, no AI rubber-banding, capped meter contribution — re-verify at every tuning pass |
| Rubber band + bonus heli stack into "can never escape" | They answer different deficits (distance vs information); test them together deliberately |
| Entity leaks across rounds | Dual cleanup (timer + round-end), acceptance test 8 |
| Last-robber advantage skews the match | Known and accepted; full-set rotation is the ready fix |
| GTA self-igniting damaged vehicles | Script-owned health, petrol tank clamped |

---

## 12. Open questions

1. After being pulled out: instant arrest, or a cuffing window breakable by a well-timed ram? (Drama vs edge cases.)
2. Cop respawn distance/delay tuning — 15s at nearest road is a guess.
3. Does the `evolves: chase` basis on the scope form already provide vehicle tasking/blip management worth building on?
4. Vehicle swap for the robber: confirmed as a witnessed event with full damage reset — needs a defined interaction (stock GTA jack, or scripted?).
5. Spectating: what do eliminated/waiting players watch? (Robber cam is the obvious answer and feeds the party-game energy.)
