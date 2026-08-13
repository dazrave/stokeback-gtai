-- Round lifecycle, roles, spawns, freeze, weather and the shared HUD. The
-- cop-only and fugitive-only brains live in their own files and read state
-- through ChaseState().
local state = { role = nil, status = {}, frozen = false }

local function setState(next)
    local merged = {}
    for key, value in pairs(state) do merged[key] = value end
    for key, value in pairs(next) do merged[key] = value end
    state = merged
end

-- Read by cop.lua / fugitive.lua.
function ChaseState()
    return state.role, state.status
end

ChaseHUD = {}

-- The mechanics live in the core toolkit; ChaseHUD stays as the mode's own
-- names for them so cop.lua and fugitive.lua read the same as ever.
ChaseHUD.notify = SBM.notify
ChaseHUD.shard  = SBM.shard

function ChaseHUD.draw(text, x, y, scale)
    SBM.drawText(text, x, y, scale or Config.hud.scale)
end

local loadModel = SBM.loadModel

-- Puts a vehicle down flat on the road. Creating one at a guessed height
-- drops it in, and GTA's physics happily lands it on its roof - which is how
-- the fugitive kept starting the round upside down.
local function placeVehicle(hash, pos)
    RequestCollisionAtCoord(pos.x, pos.y, pos.z)

    local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 25.0, false)
    local z = found and (groundZ + 1.0) or pos.z

    local vehicle = CreateVehicle(hash, pos.x, pos.y, z, pos.w, true, true)
    if not DoesEntityExist(vehicle) then return nil end

    -- Zero the pitch and roll explicitly, then let the game seat it.
    SetEntityRotation(vehicle, 0.0, 0.0, pos.w, 2, true)
    SetVehicleOnGroundProperly(vehicle)

    -- Shootable. Tyres that won't burst make the whole "aim for the tyres"
    -- brief a lie.
    SetVehicleTyresCanBurst(vehicle, true)
    SetVehicleWheelsCanBreak(vehicle, true)
    SetVehicleCanBeVisiblyDamaged(vehicle, true)
    SetVehicleStrong(vehicle, false)
    SetDisableVehiclePetrolTankDamage(vehicle, false)

    -- Destructible, not merely dentable: parts come off, the engine dies, and
    -- enough rounds into the tank ends the vehicle entirely.
    SetVehicleCanBreak(vehicle, true)
    SetVehicleEngineCanDegrade(vehicle, true)
    SetVehicleBodyHealth(vehicle, 1000.0)
    SetVehicleEngineHealth(vehicle, 1000.0)
    SetVehiclePetrolTankHealth(vehicle, 1000.0)
    Wait(50)
    SetVehicleOnGroundProperly(vehicle)

    return vehicle
end

local settleToGround = SBM.settleToGround

-- Round vehicles this client spawned; swept before each new round so fleets
-- don't stack up at the station.
local roundCars    = SBM.tracker()
local trackEntity  = roundCars.track
local sweepEntities = roundCars.sweep

local function applyLook(modelName)
    local hash = loadModel(modelName)
    if not hash then return end

    SetPlayerModel(PlayerId(), hash)
    SetModelAsNoLongerNeeded(hash)

    -- Randomised variations so multiple cops aren't clones.
    local ped = PlayerPedId()
    SetPedRandomComponentVariation(ped, 0)
    SetPedRandomProps(ped)
end

-- Wipe the yard before a round starts. sweepEntities() only knows about cars
-- THIS client spawned in THIS session, so fleets from previous rounds (and
-- everyone else's) survived and the new cars landed on top of them.
RegisterNetEvent('chase:clearArea', function(stationIndex)
    sweepEntities()

    local station = Config.stations[stationIndex or 1] or Config.stations[1]
    local origin  = station.pos
    local cleared = 0

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle)
            and #(GetEntityCoords(vehicle) - origin) < 300.0
            and IsVehicleSeatFree(vehicle, -1)
            and GetVehicleNumberOfPassengers(vehicle) == 0 then
            NetworkRequestControlOfEntity(vehicle)
            SetEntityAsMissionEntity(vehicle, true, true)
            DeleteEntity(vehicle)
            cleared = cleared + 1
        end
    end

    print(('[chase] cleared %d vehicles from the muster area'):format(cleared))
end)

RegisterNetEvent('chase:role', function(role)
    DoScreenFadeOut(600)
    Wait(700)

    sweepEntities()

    applyLook(role.isFugitive and Config.models.fugitive or Config.models.cop)
    local ped = PlayerPedId()

    -- Whichever nick got picked this round. Work out which way its road runs
    -- once, then hang the fleet and the suspect off that.
    local station = Config.stations[role.stationIndex or 1] or Config.stations[1]
    local origin  = station.pos

    local ok, node, roadHeading =
        GetClosestVehicleNodeWithHeading(origin.x, origin.y, origin.z, 1, 3.0, 0)

    local base    = ok and node or origin
    local heading = ok and roadHeading or (station.h or 0.0)
    local rad     = math.rad(heading)
    local fx, fy  = -math.sin(rad), math.cos(rad)   -- along the road
    local rx, ry  = math.cos(rad), math.sin(rad)    -- across it

    if role.isFugitive then
        -- Just up the road from everyone else, in plain view. The separation
        -- that matters is the head start, not the distance.
        local sx = base.x + fx * Config.fugitiveLead
        local sy = base.y + fy * Config.fugitiveLead

        SetEntityCoords(ped, sx, sy, base.z, false, false, false, false)
        SetEntityHeading(ped, heading)
        settleToGround(base.z)

        local hash = loadModel(Config.fugitive.cars[math.random(#Config.fugitive.cars)])
        if hash then
            local car = placeVehicle(hash, vector4(sx + rx * 2.5, sy + ry * 2.5, base.z, heading))
            SetModelAsNoLongerNeeded(hash)
            if car then
                trackEntity(car)
                -- Behind the wheel already: the head start is three seconds,
                -- and most of that was being spent walking round the bonnet.
                TaskWarpPedIntoVehicle(ped, car, -1)
            end
        end
    else
        -- On the road with everybody else, not stood in the station car park.
        -- Pushed across the kerb so nobody spawns inside the parked fleet.
        SetEntityCoords(ped,
            base.x - rx * 3.0 + math.random(-2, 2),
            base.y - ry * 3.0 + math.random(-2, 2),
            base.z, false, false, false, false)
        SetEntityHeading(ped, heading)
        settleToGround(base.z)

        -- Exactly one cop (the server's pick) spawns the shared fleet, laid
        -- out along the nearest road so nothing ends up inside a wall.
        if role.spawnFleet then
            for index, model in ipairs(Config.cop.vehicles) do
                local hash = loadModel(model)

                if hash then
                    -- Nose to tail down the kerb; the chopper gets shoved well
                    -- clear so its rotors aren't in someone's boot.
                    local along  = (index - 1) * Config.cop.fleetSpacing
                    local across = (model == 'polmav') and 18.0 or 3.0

                    local car = placeVehicle(hash, vector4(
                        base.x + fx * along + rx * across,
                        base.y + fy * along + ry * across,
                        base.z, heading))

                    SetModelAsNoLongerNeeded(hash)
                    if car then trackEntity(car) end
                end
            end
        end

        -- Into a cruiser. The fleet may have been spawned by a different
        -- client, so wait for it to replicate here before looking - and
        -- stagger the search by server id so two coppers don't both lunge for
        -- the same driver's seat on the same frame.
        CreateThread(function()
            Wait(600 + (GetPlayerServerId(PlayerId()) % 5) * 250)

            local mine = PlayerPedId()

            for _ = 1, 12 do
                if IsPedInAnyVehicle(mine, false) then break end

                local best, bestDist = nil, nil
                local me = GetEntityCoords(mine)

                for _, vehicle in ipairs(GetGamePool('CVehicle')) do
                    if DoesEntityExist(vehicle)
                        and IsVehicleSeatFree(vehicle, -1)
                        and not IsThisModelAHeli(GetEntityModel(vehicle)) then
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

        -- Held at the station until release - but only if there is still a
        -- hold left to serve. Spawning takes up to 2.5s (settleToGround waits
        -- for collision), and the server starts its head start clock 1.5s
        -- before it even sends this event, so a short hold can be over before
        -- we get here. Freezing then would be a freeze nobody ever lifts.
        if state.status.phase == nil or state.status.phase == 'headstart' then
            FreezeEntityPosition(PlayerPedId(), true)
            setState({ frozen = true })
        end
    end

    -- The golden-hour clock and weather are the framework's now (the
    -- descriptor's `clock` block) - set for everyone at the whistle, put
    -- back at the end, instead of being stamped here and never returned.

    DoScreenFadeIn(800)

    setState({ role = role.isFugitive and 'fugitive' or 'cop' })

    if role.isFugitive then
        ChaseHUD.shard('SCRAP RUN', 'You\'re the rabbit. No guns. Just wheels and nerve.')
    else
        ChaseHUD.shard('SCRAP RUN', ('Bring in %s. Tyres, not heads.'):format(role.fugitiveName or '?'))
    end
end)

-- Big centre-screen countdown. The corner clock already had the number, but
-- nobody looks at the corner in the three seconds before a chase starts.
local goFlashUntil = 0

local function bigText(text, r, g, b, scale)
    SetTextFont(1)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, 255)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentSubstringPlayerName(text)
    DrawText(0.5, 0.38)
end

CreateThread(function()
    while true do
        local status = state.status
        local left   = status and status.headstart or 0

        if state.role and status and status.phase == 'headstart' and left > 0 then
            Wait(0)
            bigText(tostring(left), 245, 200, 66, 3.0)
        elseif GetGameTimer() < goFlashUntil then
            Wait(0)
            bigText('GO!', 120, 255, 120, 3.0)
        else
            Wait(200)
        end
    end
end)

RegisterNetEvent('chase:release', function()
    goFlashUntil = GetGameTimer() + 1500
    if state.frozen then
        FreezeEntityPosition(PlayerPedId(), false)
        setState({ frozen = false })
    end

    if state.role == 'cop' then
        ChaseHUD.notify('~b~Units released.~w~ Go.')
    else
        ChaseHUD.notify('~r~They\'re coming.')
    end
end)

RegisterNetEvent('chase:status', function(status)
    setState({ status = status })

    -- The safety net for the same race the other way round: if the release
    -- event fired while we were still spawning, we never heard it. Status
    -- ticks every second and is the truth, so anything other than a head
    -- start means we should be moving.
    if state.frozen and status.phase and status.phase ~= 'headstart' then
        FreezeEntityPosition(PlayerPedId(), false)
        setState({ frozen = false })
    end
end)

RegisterNetEvent('chase:end', function(result, fugitiveName)
    if state.frozen then FreezeEntityPosition(PlayerPedId(), false) end
    setState({ role = nil, status = {}, frozen = false })

    local shards = {
        escaped  = { 'CLEAN GETAWAY', (fugitiveName or '?') .. ' vanished into the city.' },
        -- Its own card, not the escaped fallback: the fallback is how a broken
        -- round ending 'shaken' at the whistle got dressed up as CLEAN GETAWAY,
        -- which made the bug read like a result (#52).
        shaken   = { 'SHOOK THE TAIL', (fugitiveName or '?') .. ' lost them for a full minute.' },
        arrested = { 'NICKED', 'By the book. Straight to booking.' },
        shot     = { 'SUSPECT DOWN', 'The chief is FURIOUS. It was supposed to be tyres.' },
        crashed  = { 'CASE CLOSED', 'The suspect fought the scenery. Scenery won.' },
        fled     = { 'GONE', 'Left the server. The perfect crime.' },
    }

    local shard = shards[result] or shards.escaped
    ChaseHUD.shard(shard[1], shard[2])
end)

-- Player-versus-player damage is the framework's job now: the descriptor
-- says friendlyFire = 'auto' and core's referee (core/client/teams.lua)
-- switches it on for the round, blocks it between coppers, and switches it
-- back off at the end. What stays ours is the drive-by flag - drivers must
-- be able to shoot out of the window, and no other mode wants that.
CreateThread(function()
    while true do
        Wait(1000)

        if state.role then
            SetPlayerCanDoDriveBy(PlayerId(), true)
        end
    end
end)

-- The vehicle you are sitting in belongs to YOUR machine, and the owner's
-- machine decides whether incoming damage applies. Vehicles spawn damageable,
-- but the game quietly re-protects an occupied one - which is why cars turned
-- bulletproof the moment somebody got in. Re-assert it on whatever you're
-- driving, continuously, so everyone else's shots land.
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

-- Wanted level stays off for everyone: the only police tonight are humans.
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

-- Shared HUD: clock plus a role-appropriate status line.
CreateThread(function()
    while true do
        Wait(0)

        local status = state.status

        if state.role and status.phase and status.phase ~= 'idle' then
            local clock

            if status.phase == 'headstart' then
                clock = ('HEAD START  ~y~0:%02d'):format(status.headstart or 0)
            else
                local remaining = status.remaining or 0
                clock = ('%d:%02d'):format(math.floor(remaining / 60), remaining % 60)
            end

            if state.role == 'cop' then
                local line
                if status.finalAlert then
                    line = '~r~CITYWIDE ALERT - THEY\'RE ON YOUR MAP'
                elseif status.tracking then
                    line = '~r~EYES ON - GPS LOCKED'
                elseif status.shakeIn then
                    -- The clock they are losing on. Far more use than how long
                    -- ago it was: it says how long they have to find them.
                    line = ('~y~SEARCHING - %ds until they are gone'):format(status.shakeIn)
                elseif status.unseenFor then
                    line = ('~y~SEARCHING - last seen %ds ago'):format(status.unseenFor)
                else
                    line = '~c~NO CONTACT YET'
                end
                ChaseHUD.draw(clock .. '   ' .. line, Config.hud.x, Config.hud.y)
            else
                local line
                if status.finalAlert then
                    line = '~r~CITYWIDE ALERT - NOWHERE TO HIDE'
                elseif status.tracking then
                    line = '~r~SPOTTED'
                elseif status.shakeIn then
                    line = ('~g~SHAKING THEM - %ds to a clean getaway'):format(status.shakeIn)
                elseif status.unseenFor then
                    line = ('~g~HIDDEN - %ds'):format(status.unseenFor)
                else
                    line = '~g~HIDDEN'
                end
                ChaseHUD.draw(clock .. '   ' .. line, Config.hud.x, Config.hud.y)
            end
        else
            Wait(400)
        end
    end
end)


-- ===== everyone's motor tops out the same =====
-- Applied to whatever the player is sat in, not just what they started in:
-- half the round is spent nicking something else, and a cap that only covered
-- the issued cars would make hotwiring a fast one the winning move.
CreateThread(function()
    local capped = 0

    while true do
        Wait(500)

        local ped     = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if state.role and Config.matchedSpeed.enabled and vehicle ~= 0 then
            if vehicle ~= capped then
                capped = vehicle
                SetVehicleMaxSpeed(vehicle, Config.matchedSpeed.mps)
            end
        elseif capped ~= 0 then
            -- Hand the car back its own engine when the round is over, or the
            -- cap would follow it into free roam.
            if DoesEntityExist(capped) then SetVehicleMaxSpeed(capped, 0.0) end
            capped = 0
        end
    end
end)
