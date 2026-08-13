-- Round lifecycle, roles, spawns and the shared HUD. The police brain and the
-- robber brain live in their own files and read state through NickState().
--
-- The spawning here is chase's, near enough word for word: it is the code that
-- stopped cars landing on their roofs and players landing in the sky, and both
-- of those cost an evening each.
local state = {
    role   = nil,
    status = {},
    purse  = {},
    map    = { sites = {}, houses = {} },
}

local function setState(next)
    local merged = {}
    for key, value in pairs(state) do merged[key] = value end
    for key, value in pairs(next) do merged[key] = value end
    state = merged
end

-- Read by police.lua / robber.lua.
function NickState()
    return state.role, state.status
end

function NickMap()
    return state.map
end

function NickPurse()
    return state.purse
end

NickHUD = {}
NickHUD.notify = SBM.notify
NickHUD.shard  = SBM.shard

function NickHUD.draw(text, x, y, scale)
    SBM.drawText(text, x, y, scale or Config.hud.scale)
end

-- Money, the way it should read on a HUD: £4,000 rather than 4000.0.
function NickHUD.money(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    local out, count = '', 0

    for index = #text, 1, -1 do
        out = text:sub(index, index) .. out
        count = count + 1
        if count % 3 == 0 and index > 1 then out = ',' .. out end
    end

    return '£' .. out
end

local loadModel = SBM.loadModel
local roundCars = SBM.tracker()

-- Puts a vehicle down flat on the road. Creating one at a guessed height drops
-- it in and GTA happily lands it on its roof.
local function placeVehicle(hash, x, y, z, heading)
    RequestCollisionAtCoord(x, y, z)

    local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 25.0, false)
    local at = found and (groundZ + 1.0) or z

    local vehicle = CreateVehicle(hash, x, y, at, heading, true, true)
    if not DoesEntityExist(vehicle) then return nil end

    SetEntityRotation(vehicle, 0.0, 0.0, heading, 2, true)
    SetVehicleOnGroundProperly(vehicle)

    -- Shootable and breakable: bursting tyres is half the chase, and the
    -- getaway car catching fire is the other half.
    SetVehicleTyresCanBurst(vehicle, true)
    SetVehicleWheelsCanBreak(vehicle, true)
    SetVehicleCanBeVisiblyDamaged(vehicle, true)
    SetVehicleStrong(vehicle, false)
    SetDisableVehiclePetrolTankDamage(vehicle, false)
    SetVehicleCanBreak(vehicle, true)
    SetVehicleEngineCanDegrade(vehicle, true)
    SetVehicleBodyHealth(vehicle, 1000.0)
    SetVehicleEngineHealth(vehicle, 1000.0)
    SetVehiclePetrolTankHealth(vehicle, 1000.0)
    Wait(50)
    SetVehicleOnGroundProperly(vehicle)

    return vehicle
end

local function applyLook(modelName)
    local hash = loadModel(modelName)
    if not hash then return end

    SetPlayerModel(PlayerId(), hash)
    SetModelAsNoLongerNeeded(hash)

    local ped = PlayerPedId()
    SetPedRandomComponentVariation(ped, 0)
    SetPedRandomProps(ped)
end

RegisterNetEvent('nick:map', function(map)
    setState({ map = { sites = map.sites or {}, houses = map.houses or {} } })
end)

RegisterNetEvent('nick:role', function(role)
    DoScreenFadeOut(600)
    Wait(700)

    roundCars.sweep()

    applyLook(role.isRobber and Config.models.robber or Config.models.police)
    local ped = PlayerPedId()

    local spawn = role.spawn or {}

    -- Work out which way the road runs at the spawn once, then hang everything
    -- off that: hand-typed offsets park cars inside buildings.
    local ok, node, roadHeading =
        GetClosestVehicleNodeWithHeading(spawn.x or 0.0, spawn.y or 0.0, spawn.z or 0.0, 1, 3.0, 0)

    local base    = ok and node or vector3(spawn.x or 0.0, spawn.y or 0.0, spawn.z or 0.0)
    local heading = ok and roadHeading or (spawn.h or 0.0)
    local rad     = math.rad(heading)
    local fx, fy  = -math.sin(rad), math.cos(rad) -- along the road
    local rx, ry  = math.cos(rad), math.sin(rad)  -- across it

    SetEntityCoords(ped, base.x - rx * 2.0, base.y - ry * 2.0, base.z, false, false, false, false)
    SetEntityHeading(ped, heading)
    SBM.settleToGround(base.z)

    if role.isRobber then
        local hash = loadModel(Config.vehicles.ROBBER[math.random(#Config.vehicles.ROBBER)])

        if hash then
            local car = placeVehicle(hash, base.x + rx * 2.5, base.y + ry * 2.5, base.z, heading)
            SetModelAsNoLongerNeeded(hash)

            if car then
                roundCars.track(car)
                -- Behind the wheel already: the opening beat is him driving
                -- off, not walking round a bonnet while the clock runs.
                TaskWarpPedIntoVehicle(ped, car, -1)
            end
        end
    else
        -- Exactly one client spawns the shared fleet, laid nose to tail along
        -- the nearest road so nothing ends up inside a wall.
        if role.spawnFleet then
            for index, model in ipairs(Config.vehicles.POLICE) do
                local hash = loadModel(model)

                if hash then
                    local along = (index - 1) * Config.vehicles.FLEET_SPACING
                    local car = placeVehicle(hash,
                        base.x + fx * along + rx * 3.0,
                        base.y + fy * along + ry * 3.0,
                        base.z, heading)

                    SetModelAsNoLongerNeeded(hash)
                    if car then roundCars.track(car) end
                end
            end
        end

        -- Into a cruiser. The fleet may have been spawned by a different
        -- client, so wait for it to replicate - and stagger the search by
        -- server id so two coppers don't lunge for the same seat.
        CreateThread(function()
            Wait(700 + (GetPlayerServerId(PlayerId()) % 5) * 250)

            local mine = PlayerPedId()

            for _ = 1, 12 do
                if IsPedInAnyVehicle(mine, false) then break end

                local best, bestDist = nil, nil
                local me = GetEntityCoords(mine)

                for _, vehicle in ipairs(GetGamePool('CVehicle')) do
                    if DoesEntityExist(vehicle) and IsVehicleSeatFree(vehicle, -1) then
                        local gap = #(GetEntityCoords(vehicle) - me)
                        if gap < 60.0 and (not bestDist or gap < bestDist) then
                            best, bestDist = vehicle, gap
                        end
                    end
                end

                if best then
                    TaskWarpPedIntoVehicle(mine, best, -1)
                    break
                end

                Wait(400)
            end
        end)
    end

    DoScreenFadeIn(800)

    setState({ role = role.isRobber and 'robber' or 'police', purse = {} })

    if role.isRobber then
        NickHUD.shard('NICK OF TIME', 'Ten minutes. Only what you stash counts.')
    else
        NickHUD.shard('NICK OF TIME', ('%s is on the rob. Nobody knows where.'):format(role.robberName or '?'))
    end
end)

RegisterNetEvent('nick:go', function()
    if not state.role then return end
    NickHUD.notify(state.role == 'robber' and '~g~Go on then.' or '~b~Shift starts now.~w~ No contact.')
end)

RegisterNetEvent('nick:status', function(status)
    setState({ status = status })
end)

RegisterNetEvent('nick:purse', function(purse)
    setState({ purse = purse or {} })
end)

RegisterNetEvent('nick:purseNote', function(message)
    NickHUD.notify('~y~' .. tostring(message))
end)

RegisterNetEvent('nick:banked', function(value)
    NickHUD.shard('STASHED', NickHUD.money(value) .. ' safely out of your hands.')
end)

RegisterNetEvent('nick:end', function(result, robberName, stashed)
    setState({ role = nil, status = {}, purse = {}, map = { sites = {}, houses = {} } })

    local shards = {
        arrested = { 'NICKED', ('Bag confiscated. %s kept %s.'):format(robberName or '?', NickHUD.money(stashed)) },
        ['called-it'] = { 'CALLED IT A DAY', ('%s walked away with %s.'):format(robberName or '?', NickHUD.money(stashed)) },
        time     = { 'TIME', ('%s banked %s. The rest went back on the shelf.'):format(robberName or '?', NickHUD.money(stashed)) },
        fled     = { 'GONE', 'Left the server mid-job. Technically flawless.' },
        abandoned = { 'ROUND OVER', 'Called off.' },
    }

    local shard = shards[result] or shards.abandoned
    NickHUD.shard(shard[1], shard[2])
end)

-- Drivers must be able to shoot out of the window; no other mode wants that.
-- Friendly fire itself is the framework's job (descriptor friendlyFire).
CreateThread(function()
    while true do
        Wait(1000)
        if state.role then SetPlayerCanDoDriveBy(PlayerId(), true) end
    end
end)

-- The vehicle you are sitting in belongs to YOUR machine, and the owner's
-- machine decides whether incoming damage applies. GTA quietly re-protects an
-- occupied vehicle, which is why cars turn bulletproof the moment somebody
-- gets in. Re-assert it, continuously, or ramming and tyre-popping do nothing.
CreateThread(function()
    while true do
        Wait(1000)

        if state.role then
            local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)

            if vehicle ~= 0 then
                SetEntityInvincible(vehicle, false)
                SetEntityCanBeDamaged(vehicle, true)
                SetEntityProofs(vehicle, false, false, false, false, false, false, false, false)
                SetVehicleTyresCanBurst(vehicle, true)
                SetVehicleWheelsCanBreak(vehicle, true)
                SetVehicleCanBeVisiblyDamaged(vehicle, true)
                SetVehicleStrong(vehicle, false)
                SetDisableVehiclePetrolTankDamage(vehicle, false)
                SetVehicleEngineCanDegrade(vehicle, true)
                SetVehicleCanBreak(vehicle, true)
            end
        end
    end
end)

-- GTA's own stars stay off: the only police tonight are human, and this mode
-- draws its own star count off what he has stashed.
CreateThread(function()
    while true do
        Wait(1000)

        if state.role then
            SetMaxWantedLevel(0)
            SetPlayerWantedLevel(PlayerId(), 0, false)
            SetPlayerWantedLevelNow(PlayerId(), false)
        end
    end
end)

-- ===== the HUD =====
-- One line, top centre. The clock, then whichever truth belongs to your side:
-- the police see what has been REPORTED taken, he sees what is actually in the
-- bag. That gap is the mode.
local CONTACT_LINES = {
    hard = '~r~EYES ON',
    soft = '~y~SEARCHING',
    cold = '~c~NO CONTACT',
}

CreateThread(function()
    while true do
        Wait(0)

        local status = state.status

        if state.role and status.phase and status.phase ~= 'idle' then
            local remaining = status.remaining or 0
            local clock     = ('%d:%02d'):format(math.floor(remaining / 60), remaining % 60)
            local stars     = (status.stars or 0) > 0 and (' ~r~' .. string.rep('*', status.stars)) or ''

            local line

            if state.role == 'police' then
                local contact = CONTACT_LINES[status.contact or 'cold'] or CONTACT_LINES.cold

                if status.contact == 'soft' and status.unseenFor then
                    contact = ('~y~SEARCHING - %ds since anyone saw him'):format(status.unseenFor)
                end

                line = ('%s   ~w~reported taken %s%s'):format(
                    contact, NickHUD.money(status.publicTaken or 0), stars)
            else
                local purse = state.purse

                line = ('~y~bag %s   ~g~stashed %s%s'):format(
                    NickHUD.money(purse.carried or 0), NickHUD.money(purse.stashed or 0), stars)
            end

            local delta = ''
            if status.leader and status.delta then
                delta = status.delta > 0
                    and ('   ~w~%s ahead by %s'):format(status.leader.name, NickHUD.money(status.delta))
                    or  ('   ~g~leading by %s'):format(NickHUD.money(-status.delta))
            end

            NickHUD.draw(clock .. '   ' .. line .. delta, Config.hud.x, Config.hud.y)
        else
            Wait(400)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    roundCars.sweep()
end)
