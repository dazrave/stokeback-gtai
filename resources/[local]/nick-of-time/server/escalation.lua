-- Escalation: the stars he earned, the patrols they buy, the favour the police
-- can call in when they have genuinely lost him, and the members of the public
-- who phone things in.
--
-- Two pillars govern every line in this file.
--
-- PILLAR 3, AI NEVER WINS. Nothing spawned here can arrest, shoot, or end a
-- round. The patrols carry no weapons, are never given a combat task, and the
-- arrest path is a net event from a PLAYER - an NPC has no way to send one.
-- They exist to make AREAS dangerous and to generate information. That is all.
--
-- PILLAR 1, ONE DETECTION RULE. The relay and the helicopter's ping do not get
-- their own private channel to the map: they feed NickDetect.sighting() like a
-- copper's eyeballs do. So when a patrol falls behind or the helicopter goes
-- home, the picture DEGRADES through the same drifting circle as always rather
-- than snapping off. One rule, three sources.
--
-- Entities are spawned by the robber's client (it owns the area the action is
-- in, the same trick chase uses) but REGISTERED here by network id, which
-- gives the server authoritative positions for the relay and a cleanup handle
-- that survives that client crashing - the dual cleanup acceptance test 8 asks
-- for.
NickEscalation = {}

local E = Config.escalation

local state = {
    patrols     = {}, -- [vehNet] = { veh = net, ped = net, at = ms }
    heli        = nil, -- { veh = net, ped = net, endsAt = ms }
    cars        = {}, -- [vehNet] = true: script cars, swept if their owner leaves
    relay       = false,
    contactMs   = 0,
    elapsedMs   = 0,
    heliUses    = 0,
    airUnits    = 0,  -- piloted helicopters granted this round (/heli)
    pingUntil   = 0,
    airSpotUntil = 0, -- a human in a helicopter has him: ground units, now
    takeovers   = {}, -- [src] = { count, at }: the agent smith ration book
    witnesses   = {}, -- pending calls, delivered late like a real 999
    witnessAt   = 0,  -- earliest moment the next call is accepted
    lastNoise   = 0,  -- when the city last phoned anything in (sudden death)
    events      = {},
}

local function setState(next)
    local merged = {}
    for key, value in pairs(state) do merged[key] = value end
    for key, value in pairs(next) do merged[key] = value end
    state = merged
end

local function push(event)
    local events = {}
    for index, existing in ipairs(state.events) do events[index] = existing end
    events[#events + 1] = event
    setState({ events = events })
end

-- A network id, resolved to an entity the server can actually measure and
-- delete. Returns nil once the entity is gone, which is also how a stale
-- registration gets noticed.
local function resolve(netId)
    if not netId then return nil end

    -- Guarded rather than assumed. If this native is ever missing from the
    -- server build the relay simply stops working and the clients' own
    -- despawns do the tidying - which is a mode with less information in it,
    -- not a mode that throws an error into every single tick.
    if type(NetworkGetEntityFromNetworkId) ~= 'function' then return nil end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end

    return entity
end

local function bin(netId)
    local entity = resolve(netId)
    if entity then DeleteEntity(entity) end
end

-- ===== the round =====

function NickEscalation.reset()
    -- Fresh tables, not a merge: `heli = nil` in a constructor handed to a
    -- merge is simply absent, and a phantom helicopter from last round would
    -- keep the ping alive into this one.
    state = {
        patrols   = {},
        heli      = nil,
        cars      = {},
        relay     = false,
        contactMs = 0,
        elapsedMs = 0,
        heliUses  = 0,
        airUnits  = 0,
        pingUntil = 0,
        airSpotUntil = 0,
        takeovers = {},
        witnesses = {},
        witnessAt = 0,
        lastNoise = 0,
        events    = {},
    }
end

-- Is any PLAYER sat in this vehicle's seats? A script car with somebody still
-- driving it between rounds belongs to that somebody's own tracker (which
-- sweeps it at the next deal); everything else is litter.
local function playerSeated(vehicle)
    for _, src in ipairs(GetPlayers()) do
        local id  = tonumber(src)
        local ped = id and GetPlayerPed(id)

        if ped and ped ~= 0 and DoesEntityExist(ped)
            and GetVehiclePedIsIn(ped) == vehicle then
            return true
        end
    end

    return false
end

-- Everything this round put into the world, gone. Called on round end AND on
-- the resource stopping - leaked helicopters and patrol cars across rounds is
-- the most likely persistent bug in the whole mode (plan §6), so the server
-- keeps its own list precisely so it never depends on a client to tidy up.
function NickEscalation.sweep()
    for _, patrol in pairs(state.patrols) do
        bin(patrol.ped)
        bin(patrol.veh)
    end

    if state.heli then
        bin(state.heli.ped)
        bin(state.heli.veh)
    end

    -- Script cars whose spawning client is still here get swept by that
    -- client's own tracker; this pass exists for the ones whose owner
    -- disconnected mid-round (the fleet, the getaway car, a relief cruiser),
    -- which would otherwise migrate to whoever was nearby and live forever.
    for netId in pairs(state.cars) do
        local car = resolve(netId)
        if car and not playerSeated(car) then DeleteEntity(car) end
    end

    setState({ patrols = {}, heli = nil, cars = {}, relay = false, pingUntil = 0 })
end

-- ===== stars into patrols =====
-- One car per star, capped. The cap is a balance decision AND a budget one:
-- CPointRoute has forty route slots for the entire game and every vehicle on a
-- navmesh task holds one, so six pathfinders is a deliberate ceiling.
function NickEscalation.target(stars)
    return math.min(E.AI_CARS_MAX, math.max(0, (stars or 0) * E.AI_CARS_PER_STAR))
end

function NickEscalation.registerPatrol(vehNet, pedNet)
    if not vehNet then return end
    if state.patrols[vehNet] then return end

    -- Belt on the cap. The client we shipped stops at AI_CARS_MAX; anything
    -- registering meaningfully past it is not the client we shipped, and an
    -- unbounded table here is unbounded work in every tick.
    local count = 0
    for _ in pairs(state.patrols) do count = count + 1 end
    if count >= E.AI_CARS_MAX * 2 then return end

    local patrols = {}
    for id, patrol in pairs(state.patrols) do patrols[id] = patrol end
    patrols[vehNet] = { veh = vehNet, ped = pedNet, at = GetGameTimer() }

    setState({ patrols = patrols })
end

function NickEscalation.dropPatrol(vehNet)
    if not vehNet or not state.patrols[vehNet] then return end

    -- Deleted here as well as trusted to the client. The client asks for a
    -- despawn it sometimes cannot perform - the entity can be outside its
    -- routing bucket (the safehouse dive) or scoped out after an ownership
    -- migration - and a car the server deregisters without deleting is an
    -- orphan with paperwork. bin() no-ops when the client already managed it.
    local patrol = state.patrols[vehNet]
    bin(patrol.ped)
    bin(patrol.veh)

    local patrols = {}
    for id, kept in pairs(state.patrols) do
        if id ~= vehNet then patrols[id] = kept end
    end

    setState({ patrols = patrols })
end

-- Script cars (the fleet, the getaway car, relief cruisers) are reported by
-- network id exactly like the patrols, so the whistle can sweep a car whose
-- spawning client has disconnected - the one case its own tracker cannot
-- cover, and the way acceptance test 8 quietly fails on a Thursday.
function NickEscalation.registerCar(netId)
    if not netId or state.cars[netId] then return end

    -- A bound, not a budget: an evening of relief cars never gets near it,
    -- and a modded client does not get an unbounded server table.
    local count = 0
    for _ in pairs(state.cars) do count = count + 1 end
    if count >= 64 then return end

    local cars = {}
    for id in pairs(state.cars) do cars[id] = true end
    cars[netId] = true

    setState({ cars = cars })
end

function NickEscalation.registerHeli(vehNet, pedNet)
    setState({ heli = { veh = vehNet, ped = pedNet, endsAt = GetGameTimer() + E.BONUS_HELI_LIFE_S * 1000 } })
end

-- ===== contact score =====
-- The share of the round the force has genuinely had a hold of him - eyes on,
-- or simply near enough to be a problem. A LOW score is what unlocks the
-- helicopter, because the favour exists for a team chasing a rumour, not for a
-- team already sat on his bumper.
local function accrue(dt, contact, robber, robberId)
    local held = contact == 'hard'

    if not held and robber then
        for _, src in ipairs(GetPlayers()) do
            local id = tonumber(src)

            -- The robber is not "in contact" with himself. Counting his own
            -- ped (zero metres from his own position, every tick) held the
            -- score at 1.0 for the whole round, which quietly deleted the
            -- bonus helicopter from the mode - it unlocks on a LOW score.
            local ped = id and id ~= robberId and GetPlayerPed(id)

            if ped and ped ~= 0 and DoesEntityExist(ped) then
                local gap = #(GetEntityCoords(ped) - vector3(robber.x, robber.y, robber.z))
                if gap < E.CONTACT_NEAR_M then held = true break end
            end
        end
    end

    setState({
        elapsedMs = state.elapsedMs + dt * 1000,
        contactMs = state.contactMs + (held and dt * 1000 or 0),
    })
end

function NickEscalation.contactScore()
    if state.elapsedMs <= 0 then return 1.0 end
    return state.contactMs / state.elapsedMs
end

function NickEscalation.heliReady()
    if state.heliUses >= E.BONUS_HELI_USES_PER_ROUND then return false end
    if state.pingUntil > GetGameTimer() then return false end
    if state.elapsedMs < E.CONTACT_MIN_S * 1000 then return false end

    return NickEscalation.contactScore() < E.BONUS_HELI_CONTACT_THRESH
end

-- Somebody pressed the button. One use, team-wide, and the ping starts the
-- moment it is called rather than when the helicopter arrives - the police
-- earned twenty seconds of truth, not twenty seconds of rotor noise.
function NickEscalation.callHeli()
    if not NickEscalation.heliReady() then return false end

    setState({
        heliUses  = state.heliUses + 1,
        pingUntil = GetGameTimer() + E.BONUS_HELI_PING_S * 1000,
    })

    push({ kind = 'heli' })
    return true
end

-- ===== the piloted air unit =====
-- The other helicopter (Darren, game night: "I thought we could spawn and
-- pilot our own Heli?"). No detection magic on board - a flying copper's eyes
-- already reach SIGHT_AIR_RANGE through the one LOS rule - so the server's
-- whole job here is the ration book and the announcement. Returns the pad to
-- send its collector to, or false and control's reason why not.
-- She lands wherever the asker is stood (his client picks the spot, since it
-- owns that airspace); the pad only comes back as the FALLBACK for a copper
-- with no room at all, so a map with no helipad tagged is no longer a reason
-- to refuse. What the server still owns is the ration book and telling the
-- room - the robber hearing that air support is up is half of what a star
-- costs him.
-- Returns granted(bool), pad(table|nil), why(string|nil).
function NickEscalation.requestAirUnit()
    local A = Config.airUnit
    if not A or not A.ENABLED then return false, nil, 'no air support on the books.' end

    if state.airUnits >= (A.PER_ROUND or 1) then
        return false, nil, 'you have had your helicopters for one round.'
    end

    setState({ airUnits = state.airUnits + 1 })
    push({ kind = 'airunit' })

    -- No pad tagged is fine: nil simply means "no fallback", and his client
    -- will tell him to find some open ground if it comes to that.
    return true, (Config.locations.helipads or {})[1], nil
end

function NickEscalation.pinging()
    return state.pingUntil > GetGameTimer()
end

function NickEscalation.relaying()
    return state.relay
end

-- ===== witnesses =====
-- The call reports a POINT and never a direction, and it lands late. Two of
-- them in a row let the police work out a bearing themselves, which is the
-- difference between intelligence and a handout.
function NickEscalation.witness(pos, kind)
    if not Config.witness.ENABLED or not pos then return end

    -- The client holds this gap too, but the server is the copy that cannot
    -- be modded: one call per GAP_S however hard the event is spammed, or a
    -- bad actor could paper the map (config: "or a bad driver is a tracker").
    if GetGameTimer() < state.witnessAt then return end

    local band  = Config.witness.DELAY_S
    local delay = math.random(band[1], band[2]) * 1000

    local pending = {}
    for index, call in ipairs(state.witnesses) do pending[index] = call end
    pending[#pending + 1] = {
        at = GetGameTimer() + delay,
        kind = kind or 'crash',
        x = pos.x, y = pos.y, z = pos.z,
    }

    setState({
        witnesses = pending,
        witnessAt = GetGameTimer() + Config.witness.GAP_S * 1000,
        -- Stamped when the call is RAISED, not when it lands: in sudden death
        -- the noise is what breaks his quiet, and the noise happened when he
        -- hit the bus stop, not when the operator got round to it.
        lastNoise = GetGameTimer(),
    })
end

-- ===== the tick =====
-- Called once a second from round.lua with the server's own read of where he
-- is. Returns nothing: everything it decides comes back out through publish()
-- and drain(), so there is exactly one place that talks.
function NickEscalation.tick(dt, robber, contact, robberId)
    accrue(dt, contact, robber, robberId)

    -- Patrols: measured HERE, off the server's own copy of the entities, so
    -- the relay cannot be suppressed by the one client with a reason to.
    -- No line of sight check, by design (plan §5.4) - a patrol car radioing
    -- "he just went past me" does not need to still be looking at him.
    local relay = false
    local stale = {}

    for id, patrol in pairs(state.patrols) do
        local vehicle = resolve(patrol.veh)

        if not vehicle then
            stale[#stale + 1] = id
        elseif robber then
            local gap = #(GetEntityCoords(vehicle) - vector3(robber.x, robber.y, robber.z))
            if gap < E.AI_RELAY_RADIUS then relay = true end
        end
    end

    for _, id in ipairs(stale) do NickEscalation.dropPatrol(id) end

    if relay ~= state.relay then
        setState({ relay = relay })
        if relay then push({ kind = 'relay' }) end
    end

    -- The helicopter goes home on its own timer as well as at round end.
    if state.heli and GetGameTimer() > state.heli.endsAt then
        bin(state.heli.ped)
        bin(state.heli.veh)
        setState({ heli = nil })
    end

    -- 999 calls that have finished ringing.
    local waiting, now = {}, GetGameTimer()
    for _, call in ipairs(state.witnesses) do
        if now >= call.at then
            push({ kind = 'witness', saw = call.kind, x = call.x, y = call.y, z = call.z })
        else
            waiting[#waiting + 1] = call
        end
    end

    if #waiting ~= #state.witnesses then setState({ witnesses = waiting }) end
end

-- What everybody is told: how many patrols should exist (the robber's client
-- spawns them), and whether a patrol currently has him. The helicopter button
-- is NOT in here - it goes to police only, because "their heli is lit" tells
-- the robber they have lost him, which is exactly the fact the pressure meter
-- exists to withhold.
-- `sudden` turns the whole force out (SUDDEN_AI_CARS): the extra three
-- minutes are supposed to feel like a city looking for him, not like the same
-- two cars mooching about. An air spotter summons ground units the same way
-- for AIR_SPOT_HOLD_S - the helicopter's job is to START a car chase, not to
-- be one.
function NickEscalation.publish(stars, sudden)
    local target = NickEscalation.target(stars)

    if sudden then
        target = math.max(target, math.min(E.AI_CARS_MAX, E.SUDDEN_AI_CARS or 0))
    end

    if state.airSpotUntil > GetGameTimer() then
        target = math.max(target, math.min(E.AI_CARS_MAX, E.AIR_SPOT_AI_CARS or 0))
    end

    return {
        patrolTarget = target,
        relay        = state.relay,
        heliActive   = NickEscalation.pinging(),
    }
end

-- A human in a helicopter has eyes on him: ground units, now. Called from the
-- sighting path, so it is gated by exactly the same LOS rule as everything
-- else - no aircraft ever gets a free look.
function NickEscalation.airSpotted()
    local until_ = GetGameTimer() + (E.AIR_SPOT_HOLD_S or 45) * 1000
    if until_ <= state.airSpotUntil then return false end

    local fresh = state.airSpotUntil <= GetGameTimer()
    setState({ airSpotUntil = until_ })

    if fresh then push({ kind = 'airspot' }) end
    return fresh
end

-- ===== agent smith =====
-- The ration book for taking over a unit. The POSITION is not decided here -
-- round.lua hands out dispatch's belief and nothing else - so this file never
-- has to know where he actually is, which is how the no-radar rule survives a
-- feature whose whole purpose is getting closer to him.
function NickEscalation.takeoverAllowed(src)
    local T = Config.takeover
    if not T or not T.ENABLED then return false, 'nobody is taking over anything tonight.' end

    local used = state.takeovers[src] or { count = 0, at = 0 }

    if used.count >= (T.PER_ROUND or 3) then
        return false, 'you have had your go at that. Drive like everyone else.'
    end

    local wait = (used.at + (T.COOLDOWN_S or 45) * 1000) - GetGameTimer()
    if wait > 0 then
        return false, ('not yet - %d seconds.'):format(math.ceil(wait / 1000))
    end

    return true
end

function NickEscalation.takeoverUsed(src)
    local used = state.takeovers[src] or { count = 0, at = 0 }

    local takeovers = {}
    for id, entry in pairs(state.takeovers) do takeovers[id] = entry end
    takeovers[src] = { count = used.count + 1, at = GetGameTimer() }

    setState({ takeovers = takeovers })
end

-- The nearest patrol to a POINT (dispatch's belief, never the truth), so the
-- copper taking over genuinely replaces a unit that was already there. The
-- car is binned as he arrives: the force spends a patrol to put a human in
-- the area rather than getting a free extra car out of it.
function NickEscalation.consumePatrolNear(point, radius)
    if not point then return false end

    for id, patrol in pairs(state.patrols) do
        local vehicle = resolve(patrol.veh)

        if vehicle and #(GetEntityCoords(vehicle) - vector3(point.x, point.y, point.z)) < radius then
            NickEscalation.dropPatrol(id)
            return true
        end
    end

    return false
end

-- When the city last phoned something in, for sudden death's "seen or heard"
-- test. A timestamp rather than the queue: a call that has already been
-- delivered has left the queue but absolutely still happened.
function NickEscalation.lastNoiseAt()
    return state.lastNoise or 0
end

function NickEscalation.policePublish()
    return {
        heliReady    = NickEscalation.heliReady(),
        contactScore = NickEscalation.contactScore(),
    }
end

function NickEscalation.drain()
    local events = state.events
    setState({ events = {} })
    return events
end
