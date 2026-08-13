-- The garage: one identical bike and one identical biplane per racer, put
-- down where the race needs them.
--
-- Everything here happens on the racer's OWN machine, which is the machine
-- that will own the vehicle - but only ever when the server has granted it
-- (server/race.lua decides whether you have reached a leg that has vehicles in
-- it, and how often you are allowed to write one off). The client asks; it
-- never helps itself.
TriGarage = {}

local kit  = SBM.tracker() -- everything we spawn, for the sweep at the end
local memo = {
    vehicle = nil, -- the one currently on issue to this racer
    asks    = 0,   -- outstanding "send me another" requests
}

-- Which way from here to there, in GTA's heading degrees. Used to point a
-- replacement at the next checkpoint rather than at whatever the wreck was
-- facing when it stopped being a vehicle.
local function headingTo(from, to)
    if not from or not to then return nil end

    local dx, dy = to.x - from.x, to.y - from.y
    if (dx * dx + dy * dy) < 1.0 then return nil end

    return math.deg(math.atan(dx, -dy)) % 360.0
end

-- Puts a vehicle down flat on the ground. Creating one at a tagged height
-- drops it in and GTA happily lands it on its roof.
local function placeOnGround(hash, x, y, z, heading)
    RequestCollisionAtCoord(x, y, z)

    local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 25.0, false)
    local at = found and (groundZ + 1.0) or z

    local vehicle = CreateVehicle(hash, x, y, at, heading or 0.0, true, true)
    if not DoesEntityExist(vehicle) then return nil end

    SetEntityRotation(vehicle, 0.0, 0.0, heading or 0.0, 2, true)
    SetVehicleOnGroundProperly(vehicle)
    Wait(50)
    SetVehicleOnGroundProperly(vehicle)

    return vehicle
end

-- A plane, already flying. A pilot who has been through a gate and then into a
-- hillside gets put back at that gate with the engine running and speed on the
-- clock: the alternative is a two minute climb from an airfield, by which time
-- the race is somebody else's.
local function placeInAir(hash, coords, heading)
    local vehicle = CreateVehicle(hash,
        coords.x, coords.y, coords.z + (Config.respawn.AIR_RESPAWN_HEIGHT or 30.0),
        heading or 0.0, true, true)

    if not DoesEntityExist(vehicle) then return nil end

    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleForwardSpeed(vehicle, Config.respawn.AIR_RESPAWN_SPEED or 55.0)

    return vehicle
end

-- Race vehicles are ordinary vehicles: they burst, they break and they burn.
-- Crashes are the entertainment, so nothing here is made strong - it is only
-- made to START in one piece, since a replacement that arrives already smoking
-- is not a replacement.
local function prepare(vehicle)
    SetVehicleEngineHealth(vehicle, 1000.0)
    SetVehicleBodyHealth(vehicle, 1000.0)
    SetVehiclePetrolTankHealth(vehicle, 1000.0)
    SetVehicleFixed(vehicle)
    SetVehicleDirtLevel(vehicle, 0.0)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleTyresCanBurst(vehicle, true)
    SetVehicleWheelsCanBreak(vehicle, true)
    SetVehicleCanBeVisiblyDamaged(vehicle, true)
end

-- The last one is scrap by definition, so it goes - unless the racer happens
-- to still be sat in it, in which case leave it be and let the end of round
-- sweep have it. Deleting a vehicle out from under a moving player at the
-- plane transition is a very funny bug exactly once.
local function retireOld()
    local old = memo.vehicle
    if not old or not DoesEntityExist(old) then return end

    if GetVehiclePedIsIn(PlayerPedId(), false) == old then return end

    SetEntityAsMissionEntity(old, true, true)
    DeleteEntity(old)
end

-- Where the vehicles for a leg live: the transition waypoint that opens it.
local function transitionFor(leg)
    local course = TriState().course
    if not course then return nil end

    for _, waypoint in ipairs(course.waypoints) do
        if waypoint.opens == leg then return waypoint.coords end
    end

    return nil
end

-- Everything we put out, taken back in. `gentle` is the end of a race rather
-- than the end of the resource: somebody is very possibly two hundred metres
-- up in a biplane at that moment, and deleting an aeroplane out from under its
-- pilot would end the winner's evening with a long silent fall. So the screen
-- goes black, the aircraft stops existing, and they are put on the ground
-- where they were - which is a joke in itself if they were over the sea.
function TriGarage.sweep(gentle)
    memo = { vehicle = nil, asks = 0 }

    if gentle and GetVehiclePedIsIn(PlayerPedId(), false) ~= 0 then
        SBM.behindFade(function()
            kit.sweep()
            SBM.settleToGround()
        end)
        return
    end

    kit.sweep()
end

-- Ask the server for one. Sent immediately and then chased twice, because the
-- server's anti-spam cooldown can legitimately refuse the first ask (two
-- crashes in quick succession) and a racer stood next to no bike at all is the
-- one thing this mode must never leave anybody doing.
function TriGarage.request()
    memo.asks = 2
    TriggerServerEvent('tri:needVehicle')
end

CreateThread(function()
    while true do
        Wait(2500)

        if memo.asks > 0 then
            local ped = PlayerPedId()
            local has = memo.vehicle and DoesEntityExist(memo.vehicle)
                and GetVehiclePedIsIn(ped, false) == memo.vehicle

            if has then
                memo.asks = 0
            else
                memo.asks = memo.asks - 1
                TriggerServerEvent('tri:needVehicle')
            end
        end
    end
end)

-- The grant. `why` is 'transition' (you have just run/ridden up to the line of
-- them) or 'recovery' (yours is a smoking hole).
RegisterNetEvent('tri:garage', function(grant)
    if not grant or not grant.model then return end

    local course = TriState().course
    if not course then return end

    local hash = SBM.loadModel(grant.model)
    if not hash then
        return TriHUD.notify('~r~The ' .. grant.model .. ' would not load. Ask again.')
    end

    memo.asks = 0
    retireOld()

    local ped     = PlayerPedId()
    local vehicle = nil

    if grant.why == 'transition' then
        -- Laid out across the transition, one per racer, using the tag's own
        -- heading: they arrive on foot and get on. Nobody is teleported into
        -- anything - that is the whole point of a transition.
        local base = transitionFor(grant.leg)

        if base then
            local spacing = grant.leg == 'air'
                and (Config.vehicles.AIR_SPACING or 22.0)
                or  (Config.vehicles.SLOT_SPACING or 6.0)

            local rad = math.rad(base.h or 0.0)
            local from = ((grant.slot or 1) - 1) * spacing

            vehicle = placeOnGround(hash,
                base.x + math.cos(rad) * from,
                base.y + math.sin(rad) * from,
                base.z, base.h or 0.0)
        end

        if vehicle then
            TriHUD.notify(('~g~Yours is the %s with the engine still warm.'):format(grant.model))
        end
    else
        local last = course.waypoints[(grant.at or 1) - 1]
        local next_ = course.waypoints[grant.at or 1]
        local back  = (last and last.coords) or course.start

        if grant.leg == 'air' and last and last.kind == 'cp' then
            vehicle = placeInAir(hash, last.coords,
                headingTo(last.coords, next_ and next_.coords) or 0.0)
        elseif back then
            vehicle = placeOnGround(hash, back.x + 2.0, back.y + 2.0, back.z,
                headingTo(back, next_ and next_.coords) or (back.h or 0.0))
        end

        if vehicle then
            -- A recovery DOES put them in the seat: they have already done the
            -- physical bit of this transition once, and doing it again next to
            -- a hillside is not a second discipline.
            TaskWarpPedIntoVehicle(ped, vehicle, -1)
            TriHUD.notify('~y~Another one. Try to bring this one back.')
        end
    end

    SetModelAsNoLongerNeeded(hash)

    if not vehicle then
        return TriHUD.notify('~r~Nowhere to put it. Tell whoever tagged the course.')
    end

    prepare(vehicle)

    kit.track(vehicle)
    memo.vehicle = vehicle
end)
