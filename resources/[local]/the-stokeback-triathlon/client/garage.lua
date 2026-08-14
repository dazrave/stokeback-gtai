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

-- Which way from here to there, in GTA's heading degrees - anticlockwise
-- from north, so a direction vector (dx, dy) is atan2(-dx, dy). Used to point
-- a replacement at the next checkpoint rather than at whatever the wreck was
-- facing when it stopped being a vehicle. (The first cut had the arguments
-- as atan2(dx, -dy), which is this exactly 180 degrees out: every replacement
-- faced AWAY from the course, and an air respawn launched its pilot at
-- 55 m/s directly away from the next gate.)
local function headingTo(from, to)
    if not from or not to then return nil end

    local dx, dy = to.x - from.x, to.y - from.y
    if (dx * dx + dy * dy) < 1.0 then return nil end

    return math.deg(math.atan(-dx, dy)) % 360.0
end

-- Puts a vehicle down flat on the ground. Creating one at a tagged height
-- drops it in and GTA happily lands it on its roof.
local function placeOnGround(hash, x, y, z, heading)
    -- The last line of the water defence (TriDry, client/main.lua): whatever
    -- upstream let a wet position through, no vehicle is ever CREATED below
    -- the waterline. Refusing leaves the racer's retry loop asking again,
    -- which is a nuisance; a submerged sanchez is a retirement.
    if not TriDry(x, y, z) then
        print(('[tri] refused to spawn a vehicle in the sea at %.1f, %.1f - move that tag inland'):format(x, y))
        return nil
    end

    RequestCollisionAtCoord(x, y, z)

    -- The probe takes the FIRST surface going down, which next to a building
    -- is its roof. The tag was made by somebody stood on the actual ground,
    -- so an answer well above it is the wrong one - same sanity check as
    -- SBM.settleToGround.
    local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 25.0, false)
    if found and groundZ > z + 6.0 then found = false end

    local at = found and (groundZ + 1.0) or z

    local vehicle = CreateVehicle(hash, x, y, at, heading or 0.0, true, true)
    if not DoesEntityExist(vehicle) then return nil end

    -- A transition line-up is spawned as the racer clears the checkpoint
    -- BEFORE it - possibly several hundred metres of unstreamed map away.
    -- Without this an unstreamed spawn can settle straight through the world.
    SetEntityLoadCollisionFlag(vehicle, true)

    SetEntityRotation(vehicle, 0.0, 0.0, heading or 0.0, 2, true)
    SetVehicleOnGroundProperly(vehicle)
    Wait(50)
    SetVehicleOnGroundProperly(vehicle)

    return vehicle
end

-- One bay per racer, abreast from the transition tag off to its right, planes
-- further apart than bikes. Shared by the fresh line-up and by a recovery
-- that happens AT the line-up - a recovery spawned "2 metres from the tag"
-- is a recovery spawned inside whoever's vehicle is still parked in bay one.
-- The road itself, if there is one within reach. Darren: "make sure vehicles
-- such as the bikes and planes spawn in the road not on the side of it." A
-- tagged transition is somebody STOOD somewhere, which is by definition off
-- to one side - so the anchor is snapped to the nearest vehicle node and the
-- bays are laid out ALONG the carriageway (nose to tail down the road)
-- rather than across it into a hedge. Same native nick uses to drop relief
-- cars. If there is no node - a beach line-up on a future course - the tag
-- stands exactly as before.
local function onRoad(base)
    local ok, node, heading = GetClosestVehicleNodeWithHeading(
        base.x, base.y, base.z, 1, 3.0, 0)

    if not ok or not node then return base, false end

    -- A node hundreds of metres away is a different road, not this one.
    if #(vector3(node.x, node.y, node.z) - vector3(base.x, base.y, base.z)) > 40.0 then
        return base, false
    end

    return { x = node.x, y = node.y, z = node.z, h = heading or base.h or 0.0 }, true
end

local function placeAtBay(hash, grant, base)
    local spacing = grant.leg == 'air'
        and (Config.vehicles.AIR_SPACING or 22.0)
        or  (Config.vehicles.SLOT_SPACING or 6.0)

    local road
    base, road = onRoad(base)

    local rad = math.rad(base.h or 0.0)

    -- WHICH WAY THE BAYS WALK. Off-road they go abreast, (cos h, sin h),
    -- which is a start-line rank and how this always worked. ON a road they
    -- must go nose to tail instead - GTA's forward vector is
    -- (-sin h, cos h), and a rank laid abreast across a carriageway puts
    -- bay three in the oncoming lane and bay four in a hedge, which is
    -- exactly the "on the side of the road" Darren is objecting to.
    local dx, dy = math.cos(rad), math.sin(rad)
    if road then dx, dy = -math.sin(rad), math.cos(rad) end

    local from   = ((grant.slot or 1) - 1) * spacing

    -- The bay fan walks at (cos h, sin h) from the anchor, and nothing
    -- guarantees a tagged heading keeps that walk out of the sea - the
    -- first Paleto line-up pointed its fan north and fed the bikes to the
    -- tide one bay at a time. A bay that resolves wet retreats down the
    -- fan toward the anchor until it finds dry ground; two bikes sharing
    -- a bay is a better joke than one bike underwater. A wet ANCHOR is
    -- placeOnGround's refusal to make.
    while from > 0 and not TriDry(base.x + dx * from, base.y + dy * from, base.z) do
        from = math.max(0, from - spacing * 0.5)
    end

    return placeOnGround(hash,
        base.x + dx * from,
        base.y + dy * from,
        base.z, base.h or 0.0)
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

-- Ask the server for one. Sent immediately and then chased on a 2.5s beat
-- until the asks run out, because the server's anti-spam cooldown can
-- legitimately refuse the first ask (two crashes in quick succession) and a
-- racer stood next to no bike at all is the one thing this mode must never
-- leave anybody doing. Enough asks to definitely outlast the cooldown: a
-- fixed two, with an 8s cooldown, all landed inside the refusal window and
-- left exactly that racer exactly there.
function TriGarage.request()
    memo.asks = math.ceil((Config.vehicles.RECOVER_COOLDOWN_S or 8) / 2.5) + 1
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
        if base then vehicle = placeAtBay(hash, grant, base) end

        if vehicle then
            TriHUD.notify(('~g~Yours is the %s with the engine still warm.'):format(grant.model))
        end
    else
        local last = course.waypoints[(grant.at or 1) - 1]
        local next_ = course.waypoints[grant.at or 1]
        -- Dry-checked, not assumed (TriDryWaypointBefore, client/main.lua):
        -- a replacement vehicle goes to the last waypoint that passes the
        -- water test, so it lands beside its rider's own dry respawn -
        -- never at a point somebody drowned near.
        local back  = TriDryWaypointBefore(course, grant.at)

        if grant.leg == 'air' and last and last.kind == 'cp' then
            vehicle = placeInAir(hash, last.coords,
                headingTo(last.coords, next_ and next_.coords) or 0.0)
        elseif last and last.opens == grant.leg then
            -- Written off before the leg's first checkpoint: back to their
            -- OWN bay at the line-up, not a fixed offset from the tag where
            -- somebody slower's vehicle is still parked.
            vehicle = placeAtBay(hash, grant, last.coords)
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

    -- Reported by network id so the server's own ledger can sweep it when
    -- this client never gets the chance: a disconnect mid-leg, or a mate
    -- borrowing it and taking the ownership with them.
    TriggerServerEvent('tri:spawned', NetworkGetNetworkIdFromEntity(vehicle))
end)
