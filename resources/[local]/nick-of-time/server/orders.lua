-- What the clients tell us, and what the server does about it.
--
-- Every handler in here treats its client as a WITNESS, never as an authority:
-- identity and phase are checked first, and any position that matters is read
-- off the server's own copy of the peds rather than out of the event. That is
-- the whole anti-cheat posture of the mode in one sentence (plan §6) - the
-- detection maths is unspoofable because nothing a client says about where
-- anybody is ever reaches it.
--
-- Split out of round.lua when that file crossed the house ceiling. Round state
-- is reached through the NickRound accessors rather than by moving the state
-- itself: exactly one file owns the phase, and it is the one running the clock.

-- While he is in the safehouse bucket he is not on anyone's street: a stock
-- client cannot even resolve his ped, so anything claiming to see, cuff or
-- jack a vanished man is a modded client fishing. Checked on the server's own
-- bucket read, like every other fact worth checking.
local function robberVanished()
    local robber = NickRound.robber()
    return robber and (GetPlayerRoutingBucket(robber) or 0) ~= 0
end

-- ===== eyes =====
-- The one input in the entire mode that produces the truth. The event is just
-- "I can see him" - the server reads the position off its own copy of his ped.
-- The range check is the anti-cheat half: a client claiming a sighting from
-- the other side of the map is not looking at anything.
RegisterNetEvent('nick:see', function()
    local src = source
    if NickRound.phase() ~= 'active' or src == NickRound.robber() then return end
    if robberVanished() then return end

    local cop    = GetPlayerPed(src)
    local robber = NickRound.robberPed()
    if not cop or cop == 0 or not robber then return end

    local at  = GetEntityCoords(robber)
    local gap = #(GetEntityCoords(cop) - at)

    -- Generous on purpose: SIGHT_AIR_RANGE is the longest legitimate look and
    -- the client already enforces the real ground/air split. This only has to
    -- stop the impossible.
    if gap > Config.detection.SIGHT_AIR_RANGE * 1.3 then return end

    NickDetect.sighting(at, 'eyes')
end)

-- ===== the job =====
RegisterNetEvent('nick:job', function(index, method)
    local src = source
    if NickRound.phase() ~= 'active' or src ~= NickRound.robber() then return end

    local ok, why = NickHeist.startJob(tonumber(index) or 0, method, NickRound.pos())
    if not ok then
        TriggerClientEvent('nick:purseNote', src, why or 'not happening')
    end
end)

RegisterNetEvent('nick:stash', function(index)
    local src = source
    if NickRound.phase() ~= 'active' or src ~= NickRound.robber() then return end

    local ok, banked = NickHeist.stash(tonumber(index) or 0, NickRound.pos())
    if ok then
        TriggerClientEvent('nick:banked', src, banked)
    else
        TriggerClientEvent('nick:purseNote', src, banked or 'not happening')
    end
end)

-- Cashing in a nicked exotic. Same authority as everything else: the server
-- reads the car, its health and his position for itself.
RegisterNetEvent('nick:cashCar', function()
    local src = source
    if NickRound.phase() ~= 'active' or src ~= NickRound.robber() then return end

    local ok, value = NickHeist.cashCar(NickRound.vehicle(), NickRound.pos())
    if ok then
        TriggerClientEvent('nick:banked', src, value)
    else
        TriggerClientEvent('nick:purseNote', src, value or 'not happening')
    end
end)

-- "Call it a day": stood inside a safehouse, he can stop the round himself.
-- The bag banks on the way out - he is physically AT the door, so ending the
-- round there and voiding the bag was a trap with a prompt (Rory walked with
-- £0 over a £6,428 bag on the default map's first night). Checked here as
-- well as on his screen, or a robber about to be cuffed could end the round
-- from the driver's seat and rob the law of the arrest.
RegisterNetEvent('nick:callItADay', function()
    local src = source
    if NickRound.phase() ~= 'active' or src ~= NickRound.robber() then return end
    if not NickHeist.callIt(NickRound.pos()) then return end

    exports.core:EndGametype('called-it')
end)

-- ===== the catch =====

-- The client shows the prompt; the server checks the cuffs actually reach.
-- Without this any police client could end the round - and wipe the bag - from
-- the other side of the map. The SLACK halves of the numbers are the latency
-- allowance, so an honest arrest never bounces.
RegisterNetEvent('nick:arrest', function()
    local src = source
    if NickRound.phase() ~= 'active' or src == NickRound.robber() then return end
    if robberVanished() then return end

    local cop    = GetPlayerPed(src)
    local robber = NickRound.robberPed()
    if not cop or cop == 0 or not robber then return end

    if #(GetEntityCoords(cop) - GetEntityCoords(robber))
        > Config.arrest.RANGE * Config.arrest.RANGE_SLACK then return end
    if #GetEntityVelocity(robber)
        > Config.arrest.MAX_SPEED * Config.arrest.SPEED_SLACK then return end

    TriggerEvent('core:stat', src, 'arrests', 1) -- season scoreboard
    exports.core:EndGametype('arrested')
end)

-- The pull-out, refereed on the same terms. He has to be IN a vehicle that is
-- barely moving with a copper stood at the window - and NOTHING on either side
-- of this event ever hands that copper an enter-vehicle task, which is what
-- makes "he drove off in my getaway car" impossible rather than unlikely
-- (plan §5.2, jack never enter).
RegisterNetEvent('nick:jack', function()
    local src = source
    if NickRound.phase() ~= 'active' or src == NickRound.robber() then return end
    if robberVanished() then return end

    local cop    = GetPlayerPed(src)
    local robber = NickRound.robberPed()
    if not cop or cop == 0 or not robber then return end

    local vehicle = GetVehiclePedIsIn(robber)
    if not vehicle or vehicle == 0 then return end

    if #(GetEntityCoords(cop) - GetEntityCoords(robber))
        > Config.jack.RADIUS * Config.arrest.RANGE_SLACK then return end
    if #GetEntityVelocity(vehicle)
        > Config.jack.MAX_SPEED * Config.arrest.SPEED_SLACK then return end

    TriggerClientEvent('nick:jacked', NickRound.robber())
    TriggerClientEvent('nick:jackAnim', src)
end)

-- ===== information =====

-- A member of the public saw something. His client decides whether anybody was
-- LOOKING (it owns the peds around him); the server decides where and when the
-- call lands, off its own read of his position at the moment it was reported.
RegisterNetEvent('nick:witness', function(kind)
    local src = source
    if NickRound.phase() ~= 'active' or src ~= NickRound.robber() then return end

    -- The kind only ever changes what the call is CALLED. It must never carry
    -- a direction: a caller who saw a crash gives the police a point on the
    -- map and nothing else, and two points is a bearing they worked out
    -- themselves (plan §3.4). Whitelisted, so a modded client cannot invent
    -- new kinds of emergency.
    local saw = (kind == 'swap' and 'swap') or (kind == 'gunfire' and 'gunfire') or 'crash'
    NickEscalation.witness(NickRound.pos(), saw)
end)

-- Any copper can ask for the air unit; the ration book lives in escalation.
-- The pad goes back to the REQUESTER only - his client walks the spawn in
-- when he gets near it - and the approval is announced to the room by the
-- round's one voice (announce, kind 'airunit').
RegisterNetEvent('nick:airUnit', function()
    local src = source
    if NickRound.phase() ~= 'active' or src == NickRound.robber() then return end

    local pad, why = NickEscalation.requestAirUnit()
    if not pad then
        return TriggerClientEvent('nick:radio', src, why or 'no.')
    end

    TriggerClientEvent('nick:airUnitGo', src, pad)
end)

-- The robber's client spawns the patrols and the helicopter (it owns the area
-- the action is in); it reports their NETWORK IDS here so the server can
-- measure the relay off its own copy of the entities and delete them itself at
-- the end. A client is trusted to CREATE, never to decide what the creation
-- means.
RegisterNetEvent('nick:patrolUp', function(vehNet, pedNet)
    local src = source
    if NickRound.phase() ~= 'active' or src ~= NickRound.robber() then return end

    NickEscalation.registerPatrol(tonumber(vehNet), tonumber(pedNet))
end)

RegisterNetEvent('nick:patrolDown', function(vehNet)
    local src = source
    if src ~= NickRound.robber() then return end

    NickEscalation.dropPatrol(tonumber(vehNet))
end)

RegisterNetEvent('nick:heliUpAck', function(vehNet, pedNet)
    local src = source
    if NickRound.phase() ~= 'active' or src ~= NickRound.robber() then return end

    NickEscalation.registerHeli(tonumber(vehNet), tonumber(pedNet))
end)

-- Script cars - the muster fleet, the getaway car, relief cruisers - reported
-- by network id like the patrols are, from whichever client spawned one. The
-- client's own tracker is still the first sweep; the server's copy exists for
-- the client that disconnects mid-round, whose cars would otherwise migrate
-- to whoever was stood nearby and outlive the round (acceptance test 8).
RegisterNetEvent('nick:carUp', function(netId)
    if NickRound.phase() == 'idle' then return end

    NickEscalation.registerCar(tonumber(netId))
end)

-- Any copper can call the favour in; it is team-wide and it is one use.
RegisterNetEvent('nick:heliCall', function()
    local src = source
    if NickRound.phase() ~= 'active' or src == NickRound.robber() then return end

    if not NickEscalation.callHeli() then
        TriggerClientEvent('nick:radio', src, 'no, and stop asking.')
    end
end)

-- OneSync culls distant players out of existence client-side, which would make
-- a helicopter's entire job impossible - it would be flying over a city with
-- nobody in it. Airborne police get a bigger bubble (plan §5.3); 0.0 hands
-- them back to the default one.
RegisterNetEvent('nick:airborne', function(up)
    local src = source
    if NickRound.phase() == 'idle' or src == NickRound.robber() then return end

    SetPlayerCullingRadius(src, up and Config.escalation.CULLING_RADIUS_AIR or 0.0)
end)

-- ===== the dive =====
-- A routing bucket is the only way a player genuinely disappears rather than
-- merely being hard to see - the whole force can drive through the doorway and
-- never know. Granted by the server, and only ever stood in a safehouse zone,
-- checked against the server's own read of his position, so a modded client
-- cannot decide to be invisible on the open road.
RegisterNetEvent('nick:vanish', function(hidden)
    local src = source
    if src ~= NickRound.robber() then return end

    if hidden then
        if NickRound.phase() ~= 'active' then return end
        if not NickHeist.nearHouse(NickRound.pos()) then return end
        if NickRound.vehicle() then return end -- the dive is on foot, by definition

        -- The clear window, refereed on the server's own picture. Hard
        -- contact means somebody is watching him do it - a copper's eyes, a
        -- patrol by the door, the helicopter's ping - and entry under
        -- observation gets the loud SPOTTED instead of the vanish (plan
        -- §4.4). The client used to judge this itself off the broadcast
        -- contact state, which was both a leak and an honesty system.
        if NickDetect.contact() == 'hard' then
            return TriggerClientEvent('nick:spotted', src)
        end

        SetPlayerRoutingBucket(src, Config.safehouses.HIDDEN_BUCKET)
        return TriggerClientEvent('nick:hidden', src)
    end

    SetPlayerRoutingBucket(src, 0)
end)
