# Scaffolding a new gametype

The checklist for turning an approved scope (a `docs/modes/<slug>.md` design
doc with a `scoped` umbrella issue) into a mode skeleton the build loop can
work on. One pass per gametype, done by a human or an agent session with the
owner watching.

## 1. The resource

New mode: copy `chase`'s shape into `resources/[local]/<slug>/` — it is the
reference framework mode. The manifest wiring that matters:

```lua
shared_scripts { '@core/shared/loadouts.lua', 'config.lua' }  -- loadouts only if it names a kit
client_scripts { '@core/client/lib.lua', 'client/main.lua' }  -- lib.lua FIRST
server_script  'server/round.lua'
dependency 'core'
```

Evolving an existing mode instead? Work lands in that mode's folder; skip to
step 3.

## 2. The declaration

`server/round.lua` registers the descriptor on start of itself AND of core
(copy chase's `register()` idiom — a core reboot wipes the registry):

```lua
exports.core:RegisterGametype('<slug>', {
    label        = '<The Name>',
    teams        = 'coop',            -- or 'ffa', or an explicit team list
    population   = 'empty',           -- 'empty' | 'sparse' | 'alive'
    police       = 'off',             -- 'ambient' | 'off' | 'custom'
    friendlyFire = 'auto',
    respawn      = { kind = 'where-you-fell', delay = 8 },
    clock        = { hour = 22, weather = 'FOG', freeze = true },
    roundSeconds = 600,
    minPlayers   = 2,
    hooks        = { OnStart = onStart, OnEnd = onEnd, OnTick = onTick },
})
```

The framework gives you `/  <slug> start|stop`, the world claim, teams, FF
refereeing, the clock, and full restoration however the round ends. The mode
is: a config, its rules, its drama.

## 3. The locations

Every tagged location from the scope doc's Locations table lands in
`config.lua` as named data — never inline coordinates in behaviour files:

```lua
Config.locations = {
    pubDoor = { x = 215.4, y = -810.1, z = 30.7, h = 340.0, role = 'player spawn' },
}
```

These coordinates were captured by a person standing on them, which is what
lets follow-up issues stay `auto` under the no-guessed-coordinates rule.

## 4. Registration touch-points

The framework derives the mode list from `RegisterGametype`, so `ALL_MODES`
needs nothing. Still manual:

- [ ] `server.cfg` — `ensure <slug>` (ships dormant; nothing runs until `/<slug> start`)
- [ ] `web/server.py` — add the slug to the `MODES` whitelist (idea box targeting)
- [ ] `AGENTS.md` — mode label axis + config lever table rows
- [ ] `README.md` — modes table
- [ ] `.github/ISSUE_TEMPLATE/change.yml` — mode dropdown
- [ ] `telemetry` `/resetgame` stop/start lists (still hardcoded)
- [ ] `core/server/vote.lua` `/votenext` map, if the mode should be voteable

## 5. First deploy

At a lull, never mid-round: `scripts/luacheck.sh`, then
`scripts/deploy.sh <slug>` (deploy.sh refreshes manifests before restarting —
a new resource or changed manifest needs it).
