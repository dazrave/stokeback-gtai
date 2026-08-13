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
    relay       = false,
    contactMs   = 0,
    elapsedMs   = 0,
    heliUses    = 0,
    pingUntil   = 0,
    witnesses   = {}, -- pending calls, delivered late like a real 999
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
        relay     = false,
        contactMs = 0,
        elapsedMs = 0,
        heliUses  = 0,
        pingUntil = 0,
        witnesses = {},
        events    = {},
    }
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

    setState({ patrols = {}, heli = nil, relay = false, pingUntil = 0 })
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

    local patrols = {}
    for id, patrol in pairs(state.patrols) do patrols[id] = patrol end
    patrols[vehNet] = { veh = vehNet, ped = pedNet, at = GetGameTimer() }

    setState({ patrols = patrols })
end

function NickEscalation.dropPatrol(vehNet)
    if not vehNet or not state.patrols[vehNet] then return end

    local patrols = {}
    for id, patrol in pairs(state.patrols) do
        if id ~= vehNet then patrols[id] = patrol end
    end

    setState({ patrols = patrols })
end

function NickEscalation.registerHeli(vehNet, pedNet)
    setState({ heli = { veh = vehNet, ped = pedNet, endsAt = GetGameTimer() + E.BONUS_HELI_LIFE_S * 1000 } })
end

-- ===== contact score =====
-- The share of the round the force has genuinely had a hold of him - eyes on,
-- or simply near enough to be a problem. A LOW score is what unlocks the
-- helicopter, because the favour exists for a team chasing a rumour, not for a
-- team already sat on his bumper.
local function accrue(dt, contact, robber)
    local held = contact == 'hard'

    if not held and robber then
        for _, src in ipairs(GetPlayers()) do
            local id = tonumber(src)
            local ped = id and GetPlayerPed(id)

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

    local band  = Config.witness.DELAY_S
    local delay = math.random(band[1], band[2]) * 1000

    local pending = {}
    for index, call in ipairs(state.witnesses) do pending[index] = call end
    pending[#pending + 1] = {
        at = GetGameTimer() + delay,
        kind = kind or 'crash',
        x = pos.x, y = pos.y, z = pos.z,
    }

    setState({ witnesses = pending })
end

-- ===== the tick =====
-- Called once a second from round.lua with the server's own read of where he
-- is. Returns nothing: everything it decides comes back out through publish()
-- and drain(), so there is exactly one place that talks.
function NickEscalation.tick(dt, robber, contact)
    accrue(dt, contact, robber)

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
function NickEscalation.publish(stars)
    return {
        patrolTarget = NickEscalation.target(stars),
        relay        = state.relay,
        heliActive   = NickEscalation.pinging(),
    }
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
