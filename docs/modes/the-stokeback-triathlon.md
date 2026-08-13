# Gametype scope: The Stokeback Triathlon (rory)

**Basis:** new mode · **Slug:** `the-stokeback-triathlon` · **Submitted:** 2026-08-13 18:55 UTC

## The pitch

Someone in Stoke has decided to organise a triathlon without actually checking what a triathlon is.

Everyone starts together in an obstacle-course foot race. Survive that and you jump onto motocross bikes for a cross-country race over hills, dirt tracks and jumps. Reach the end of that and, for reasons nobody questions, the final discipline is biplane racing.

The biplane course gets increasingly sketchy, sending everyone through tight gates and around buildings until somebody crosses the final finish line.

The joke is the escalation. It starts vaguely like an organised sporting event and ends with six blokes desperately trying not to fly aeroplanes into buildings.

## The core loop

All players spawn together at the starting line.

A countdown starts and everyone sets off simultaneously.

Leg 1 — Obstacle Run

Players race on foot through a checkpoint course lasting roughly 5 minutes.

The route uses the GTA environment and simple placed props to create obstacles rather than requiring a complicated new obstacle system.

Players need to sprint, climb, jump and navigate through the checkpoints.

Death/failure returns the player to their most recent checkpoint.

The final running checkpoint leads directly into the motocross transition.

Leg 2 — Motocross

Identical motocross bikes are waiting for the racers.

Players physically reach and get onto their bike rather than being teleported into the next stage.

The bike course should take roughly 5 minutes and be primarily cross-country: hills, dirt tracks, steep climbs/descents, ridges and jumps rather than normal road racing.

Players must pass through every checkpoint in order.

If a player dies or destroys/loses their bike, they respawn at their latest checkpoint with a replacement bike.

The final motocross checkpoint leads into the airfield/plane transition.

Leg 3 — Biplane

Identical biplanes are waiting for everyone.

Again, players physically abandon their bikes, reach their plane and take off.

The flying course should take roughly 5 minutes.

Unlike the motocross section, this is primarily about precision. Players fly through sequential aerial gates, with the course becoming progressively tighter and more ridiculous.

It should include turns around landmarks/buildings and tight sections where crashes between players or into scenery are likely.

If the player dies or destroys the plane, they respawn at their latest checkpoint with a replacement plane.

First player through the final aerial checkpoint wins.

Once first place finishes, everyone else has 60 seconds to finish before receiving a DNF.

Normal player/vehicle collision stays enabled. Accidental and deliberate crashes are part of the race.

No weapons.

## Win / lose

Winner: first player to complete every checkpoint across all three disciplines and cross the final biplane finish.

When the winner finishes:

Display the winner/big-moment card.
Start a 60-second final-finisher countdown.
Other players continue racing.
Anyone crossing the finish during that minute receives their finishing position.
Anyone still racing when the countdown expires receives a DNF.

The round also has a configurable maximum duration, initially around 20 minutes.

If nobody has finished when the main timer expires, rank players by race progress: discipline, checkpoint reached, then distance/progress towards the next checkpoint if practical.

Nobody is permanently eliminated by death or destroying a vehicle.

## Night one minimum

Night One

Keep this deliberately small.

One fixed course.

One running route, one motocross route and one biplane route.

Approximately 5 minutes per section.

Sequential checkpoints.

One identical motocross bike model for everyone.

One identical biplane model for everyone.

Running uses existing world geometry plus only simple props where needed.

Motocross uses the existing terrain: hills, dirt tracks, climbs, descents and a few natural/simple jumps.

Plane course uses aerial checkpoints around existing scenery/buildings.

Respawn at latest checkpoint.

Vehicle legs respawn the player with a fresh vehicle.

Position/progress shown to players.

First finisher wins.

60 seconds for everyone else to finish.

DNF after that.

No weapons.

No AI.

No powerups.

No bespoke stunt/obstacle system.

No branching routes.

No vehicle selection.

No multiple courses.

If four people can play this once and immediately demand another race, Night One has worked.

## The wishlist

Multiple triathlon courses.

Data-driven course definitions so new races are mostly checkpoints/transitions in config rather than new code.

Alternative obstacle-course layouts.

More elaborate obstacle props and moving hazards.

Multiple motocross routes.

Huge motocross jumps.

Risk/reward shortcuts.

Different vehicle combinations.

Randomised vehicle combinations — including increasingly stupid definitions of "triathlon".

Alternative aircraft.

More difficult aerial courses.

Extremely tight optional aerial shortcuts.

Course hazards.

Split times for each discipline.

Fastest runner / rider / pilot awards.

Personal and season records.

Ghost/personal-best times if practical.

Spectator cameras around particularly dangerous obstacles.

SBM TV moments triggered at transitions and notorious crash locations.

Multiple race presets selectable through voting.

## Framework features

- **Teams:** ffa
- **Population:** sparse
- **Police:** off
- **Respawn policy:** enabled at latest completed checkpoint.  During running, respawn player on foot.  During motocross, respawn player with the configured motocross bike.  During biplane, respawn player with the configur
- **Clock / weather override:** fixed per course/config. Night One should use conditions where the terrain and aerial checkpoints are clearly visible.
- **Round timer:** yes. Initial target approximately 20 minutes.

## config.lua knobs

```
Everything we might shout about on Friday should be configurable.

Main round time limit
Post-winner finish window (default 60 seconds)
Starting countdown duration
Running checkpoint radius
Motocross checkpoint radius
Plane gate/checkpoint radius
Respawn delay
Respawn penalty
Running course checkpoints
Motocross course checkpoints
Plane course checkpoints/gates
Player spawn points
Transition locations
Motocross vehicle model
Plane model
Vehicle spawn points/headings
Vehicle replacement delay
Population setting
Police setting
Clock
Weather
Whether player collision is enabled
Out-of-bounds/reset distance if required
Checkpoint miss/reset behaviour
DNF behaviour
Course/discipline target times where needed for balancing
```

## Locations (verified tags)

_(no verified tags attached)_

## Locations still needed

Do not guess any coordinates. These all need tagging in game.

Running
Overall starting area
Individual player start/spawn positions
Running checkpoint 1
Running checkpoint 2
Running checkpoint 3
etc. for every required running checkpoint
Any obstacle/prop placement positions required
Running-to-motocross transition checkpoint
Motocross
Individual motocross bike spawn positions and headings
Motocross checkpoint 1
Motocross checkpoint 2
etc. for the entire cross-country route
Specific hill climbs
Ridge crossings
Descents
Dirt-track sections
Any deliberate jump locations
Motocross-to-plane transition checkpoint

The route should deliberately seek out terrain rather than following roads.

Biplane
Individual biplane spawn positions and headings
Takeoff/start gate
Every aerial checkpoint/gate in order
Building/landmark turn points
Any particularly tight gate locations
Final aerial finish gate

Plane checkpoints need enough information to define their position and, if the checkpoint system requires it, intended orientation/direction.

## Acceptance criteria

Night One works if:

3 players can start and complete a race.
4–6 players can start simultaneously without the race state breaking.
All players begin on foot.
Players must complete running checkpoints in order.
Players physically transition from running to motocross.
Every player receives the correct motocross bike.
The motocross route genuinely uses off-road/hilly terrain rather than becoming a road race.
Players must complete motocross checkpoints in order.
A dead/stranded motocross player can recover at their latest checkpoint with a working replacement bike.
Players physically transition from motocross to biplanes.
Every player receives the correct biplane.
Plane gates must be completed in order.
A crashed pilot can recover at their latest checkpoint with a working replacement plane.
Crashing never permanently removes somebody from the race.
First player through the final gate is correctly declared the winner.
Remaining racers receive 60 seconds to finish.
Players finishing during that window receive the correct position.
Remaining players receive a DNF when the window expires.
The round cannot run indefinitely.
A normal successful race takes roughly 15 minutes.
The mode can be immediately restarted for another race.
There are no weapons.
There is at least one massive motocross cock-up.
At least one biplane is almost certainly written off.
Everyone argues about whose fault a collision was.
Somebody asks to play it again.
