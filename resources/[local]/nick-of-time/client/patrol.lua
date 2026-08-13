-- AI patrols and the bonus helicopter, spawned on the ROBBER'S own client.
--
-- Same reasoning as chase's AI units: that machine owns the area the action is
-- happening in, so the driving AI runs locally where it matters instead of at
-- the mercy of entity ownership. What is different here is that every entity's
-- network id goes straight to the server, which then measures the relay off
-- its own copy of them and deletes them itself at the end of the round. A
-- client is trusted to create; it is never trusted to decide what the creation
-- means, and it is never the only thing standing between a round and a leaked
-- helicopter.
--
-- PILLAR 3 IS ABSOLUTE. Nothing in this file is armed, nothing is given a
-- combat task, and nothing can end a round. Their entire job is to make the
-- streets near them a worse place to be seen in.
local units = { patrols = {}, heli = nil, nextSpawn = 0 }

local E = Config.escalation

-- Normal driving: they obey lights, they take the long way round, they get
-- stuck behind a bus. A well-driven getaway genuinely loses them, which is the
-- whole point of them not being rubber-banded (plan §5.4).
local DRIVING_STYLE = 786603

local function isRobber()
    local role, status = NickState()
    return role == 'robber' and status.phase == 'active'
end

-- How many patrols are actually near him. The pressure meter reads this so the
-- AI half of the bar can be capped (plan §4.5); with no radius it is simply
-- how many exist.
function NickPatrolCount(radius)
    if not radius then return #units.patrols end

    local me    = GetEntityCoords(PlayerPedId())
    local close = 0

    for _, unit in ipairs(units.patrols) do
        if unit.vehicle and DoesEntityExist(unit.vehicle)
            and #(GetEntityCoords(unit.vehicle) - me) < radius then
            close = close + 1
        end
    end

    return close
end

local function despawn(unit)
    if not unit then return end

    if unit.vehNet then TriggerServerEvent('nick:patrolDown', unit.vehNet) end

    for _, entity in ipairs({ unit.ped or 0, unit.vehicle or 0 }) do
        if entity ~= 0 and DoesEntityExist(entity) then
            SetEntityAsMissionEntity(entity, true, true)
            DeleteEntity(entity)
        end
    end
end

local function clearAll()
    for _, unit in ipairs(units.patrols) do despawn(unit) end

    if units.heli then
        for _, entity in ipairs({ units.heli.ped or 0, units.heli.vehicle or 0 }) do
            if entity ~= 0 and DoesEntityExist(entity) then
                SetEntityAsMissionEntity(entity, true, true)
                DeleteEntity(entity)
            end
        end
    end

    units = { patrols = {}, heli = nil, nextSpawn = 0 }
end

-- A bit of road far enough away that they arrive rather than appear. Sampled
-- around him, so where they come from is as unpredictable as the map allows.
local function approachNode(from)
    for _ = 1, 8 do
        local angle    = math.random() * 6.2832
        local distance = E.AI_SPAWN_DISTANCE[1]
            + math.random() * (E.AI_SPAWN_DISTANCE[2] - E.AI_SPAWN_DISTANCE[1])

        local ok, node, heading = GetClosestVehicleNodeWithHeading(
            from.x + math.cos(angle) * distance,
            from.y + math.sin(angle) * distance,
            from.z, 1, 3.0, 0)

        if ok then return node, heading end
    end

    return nil
end

local function spawnPatrol(me, target)
    local node, heading = approachNode(me)
    if not node then return end

    local carHash = SBM.loadModel(E.AI_MODELS[math.random(#E.AI_MODELS)])
    local copHash = SBM.loadModel(E.AI_DRIVER)
    if not carHash or not copHash then return end

    local vehicle = CreateVehicle(carHash, node.x, node.y, node.z + 0.5, heading, true, true)
    SetModelAsNoLongerNeeded(carHash)
    if not DoesEntityExist(vehicle) then return end

    SetEntityRotation(vehicle, 0.0, 0.0, heading, 2, true)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleEngineOn(vehicle, true, true, false)

    -- Sirens on. Spatialised noise IS the mechanic (plan §4.2): it is the only
    -- warning he gets while he is stood inside a shop with his back to the
    -- street, and it is the reason a patrol makes an AREA dangerous.
    SetVehicleSiren(vehicle, true)
    SetVehicleHasMutedSirens(vehicle, false)

    local driver = CreatePedInsideVehicle(vehicle, 26, copHash, -1, true, true)
    SetModelAsNoLongerNeeded(copHash)

    if not DoesEntityExist(driver) then
        SetEntityAsMissionEntity(vehicle, true, true)
        DeleteEntity(vehicle)
        return
    end

    -- The guarantees, in one place. No weapons to fire, no events to react to,
    -- no combat task ever issued: a patrol cannot shoot him, cannot arrest him
    -- and cannot end the round even by accident.
    RemoveAllPedWeapons(driver, true)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetPedFleeAttributes(driver, 0, false)
    SetPedCanBeTargetted(driver, false)
    SBM.hardenPed(driver) -- a patrol dying just leaves a car in the road

    SetDriverAbility(driver, 0.8)
    SetDriverAggressiveness(driver, 0.4) -- a tail, not a battering ram
    SetPedKeepTask(driver, true)

    -- Follow, at a distance, forever. Never TaskVehicleChase: chase closes and
    -- rams, which is a catch, and catches belong to humans.
    TaskVehicleFollow(driver, vehicle, target, 25.0, DRIVING_STYLE, E.AI_FOLLOW_OFFSET)

    local vehNet = NetworkGetNetworkIdFromEntity(vehicle)
    local pedNet = NetworkGetNetworkIdFromEntity(driver)
    SetNetworkIdCanMigrate(vehNet, true) -- so it outlives this client leaving

    units.patrols[#units.patrols + 1] = {
        vehicle = vehicle, ped = driver,
        vehNet = vehNet, pedNet = pedNet,
        at = GetGameTimer(),
    }

    TriggerServerEvent('nick:patrolUp', vehNet, pedNet)
end

-- The ladder, once a second. Everything is capped by the server's target,
-- which is capped by AI_CARS_MAX - and that cap is a CPointRoute budget as
-- much as a balance decision: forty route slots exist for the entire game and
-- every vehicle on a navmesh task holds one.
CreateThread(function()
    while true do
        Wait(1000)

        local _, status = NickState()

        if not isRobber() then
            if #units.patrols > 0 or units.heli then clearAll() end
        else
            local ped    = PlayerPedId()
            local me     = GetEntityCoords(ped)
            local now    = GetGameTimer()
            local target = math.min(E.AI_CARS_MAX, status.patrolTarget or 0)

            -- Bin the ones that have lost him, crashed out, or been left
            -- behind entirely. This is the client half of the dual cleanup.
            local kept = {}
            for _, unit in ipairs(units.patrols) do
                local alive = unit.vehicle and DoesEntityExist(unit.vehicle)
                    and unit.ped and DoesEntityExist(unit.ped)

                if alive and #(GetEntityCoords(unit.vehicle) - me) < E.AI_DESPAWN_DISTANCE
                    and #kept < target then
                    kept[#kept + 1] = unit
                else
                    despawn(unit)
                end
            end
            units.patrols = kept

            -- A vehicle task quietly expires; re-issuing keeps them coming
            -- without re-issuing every tick (which would restart the task's
            -- animation and read as a car sitting still doing nothing).
            for _, unit in ipairs(units.patrols) do
                if (now - unit.at) > E.AI_RETASK_MS then
                    unit.at = now
                    TaskVehicleFollow(unit.ped, unit.vehicle, ped, 25.0, DRIVING_STYLE, E.AI_FOLLOW_OFFSET)
                    SetVehicleSiren(unit.vehicle, true)
                end
            end

            -- They arrive over time. Six cars materialising the second he
            -- banks his fifth grand would read as a punishment; one at a time
            -- reads as the net closing.
            if #units.patrols < target and now >= units.nextSpawn then
                units.nextSpawn = now + E.AI_SPAWN_EVERY_MS
                spawnPatrol(me, ped)
            end
        end
    end
end)

-- ===== the favour =====
-- Cosmetic, high, and brief. The PING is the favour - this is the noise that
-- explains it, and the reason he looks up and knows exactly how much trouble
-- he is in. It cannot see, cannot shoot and cannot land on anybody.
RegisterNetEvent('nick:heliUp', function()
    if not isRobber() then return end
    if units.heli then return end

    local ped = PlayerPedId()
    local me  = GetEntityCoords(ped)

    local heliHash  = SBM.loadModel(E.BONUS_HELI_MODEL)
    local pilotHash = SBM.loadModel(E.BONUS_HELI_PILOT)
    if not heliHash or not pilotHash then return end

    local heli = CreateVehicle(heliHash, me.x, me.y, me.z + E.BONUS_HELI_HEIGHT, 0.0, true, true)
    SetModelAsNoLongerNeeded(heliHash)
    if not DoesEntityExist(heli) then return end

    local pilot = CreatePedInsideVehicle(heli, 26, pilotHash, -1, true, true)
    SetModelAsNoLongerNeeded(pilotHash)

    if not DoesEntityExist(pilot) then
        SetEntityAsMissionEntity(heli, true, true)
        DeleteEntity(heli)
        return
    end

    RemoveAllPedWeapons(pilot, true)
    SetBlockingOfNonTemporaryEvents(pilot, true)
    SBM.hardenPed(pilot)
    SetVehicleEngineOn(heli, true, true, false)
    SetHeliBladesFullSpeed(heli)
    SetVehicleSearchlight(heli, true, true)

    -- Guarded: this native has a lot of arguments and a lot of opinions, and
    -- a helicopter that merely hovers is a perfectly good helicopter. The
    -- twenty seconds of truth do not depend on it in any way.
    pcall(function()
        TaskHeliMission(pilot, heli, 0, ped, 0.0, 0.0, 0.0, 4, 30.0, 10.0, -1.0,
            math.floor(E.BONUS_HELI_HEIGHT + 25.0), math.floor(E.BONUS_HELI_HEIGHT - 15.0), 0.0, 0)
    end)

    local vehNet = NetworkGetNetworkIdFromEntity(heli)
    local pedNet = NetworkGetNetworkIdFromEntity(pilot)
    SetNetworkIdCanMigrate(vehNet, true)

    units.heli = { vehicle = heli, ped = pilot, vehNet = vehNet, pedNet = pedNet }
    TriggerServerEvent('nick:heliUpAck', vehNet, pedNet)

    -- It goes home on its own timer as well as at round end and on the
    -- server's own sweep. Three ways out, because a leaked helicopter is the
    -- single most visible bug this mode could ship.
    CreateThread(function()
        Wait(E.BONUS_HELI_LIFE_S * 1000)

        if units.heli and units.heli.vehicle == heli then
            for _, entity in ipairs({ pilot, heli }) do
                if DoesEntityExist(entity) then
                    SetEntityAsMissionEntity(entity, true, true)
                    DeleteEntity(entity)
                end
            end
            units.heli = nil
        end
    end)
end)

RegisterNetEvent('nick:end', clearAll)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearAll()
end)
