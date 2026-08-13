-- The police brain: eyes, the map, the arrest, and the one bit of help the
-- law gets on a straight road.
--
-- The eyes are chase's, because chase already paid for the two mistakes in
-- them: trace CAR to CAR rather than ped to ped (the line-of-sight test only
-- ignores the two entities you name, so two people in cars have four bits of
-- bodywork between them and a bumper-to-bumper pursuit never counts as a
-- sighting), and check the screen as well as the distance.
local blips = { track = nil, ring = nil, search = nil, radius = 0, sites = {}, pings = {} }
local fleet = SBM.tracker()

local D = Config.detection

local function clearBlips()
    -- Named one at a time rather than through a list: a table constructor
    -- with a nil in the middle of it truncates, so { track, ring, search }
    -- with no track would silently leave the other two on the map forever.
    for _, key in ipairs({ 'track', 'ring', 'search' }) do
        if blips[key] and DoesBlipExist(blips[key]) then RemoveBlip(blips[key]) end
    end
    for _, blip in ipairs(blips.sites) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    for _, ping in ipairs(blips.pings) do
        if DoesBlipExist(ping.blip) then RemoveBlip(ping.blip) end
    end

    blips = { track = nil, ring = nil, search = nil, radius = 0, sites = {}, pings = {} }
end

local function robberPed(status)
    if not status.robberId then return nil end

    local playerId = GetPlayerFromServerId(status.robberId)
    if playerId == -1 then return nil end

    local ped = GetPlayerPed(playerId)
    if not DoesEntityExist(ped) then return nil end

    return ped
end

-- ===== eyes =====
-- The only thing in the whole mode that produces the truth. Runs at
-- LOS_TICK_HZ rather than every frame: five looks a second is quicker than
-- anyone can drive round a corner, and it keeps the raycast off the frame
-- budget in a city full of traffic.
CreateThread(function()
    while true do
        Wait(math.floor(1000 / math.max(1, D.LOS_TICK_HZ)))

        local role, status = NickState()

        if role == 'police' and status.phase == 'active' then
            local ped = robberPed(status)

            if ped and not IsEntityDead(ped) then
                local me    = PlayerPedId()
                local dist  = #(GetEntityCoords(ped) - GetEntityCoords(me))
                local range = (IsPedInAnyVehicle(me, false) and IsPedInFlyingVehicle(me))
                    and D.SIGHT_AIR_RANGE or D.SIGHT_GROUND_RANGE

                local myVehicle    = GetVehiclePedIsIn(me, false)
                local theirVehicle = GetVehiclePedIsIn(ped, false)
                local from = myVehicle ~= 0 and myVehicle or me
                local to   = theirVehicle ~= 0 and theirVehicle or ped

                if dist < range
                    and IsEntityOnScreen(to)
                    and HasEntityClearLosToEntity(from, to, D.LOS_FLAGS) then
                    -- Just "I can see him": the server reads the position off
                    -- its own copy of his ped, so no client coords to trust.
                    TriggerServerEvent('nick:see')
                end
            end
        end
    end
end)

-- ===== the map =====
-- Sprites are deliberately boring: 161 (the target reticle) and plain circles
-- are the two chase has actually verified render sensibly at every zoom.
local function ensureSiteBlips()
    if #blips.sites > 0 then return end

    for _, site in ipairs(NickMap().sites or {}) do
        local blip = AddBlipForCoord(site.x, site.y, site.z)
        SetBlipSprite(blip, 1)
        SetBlipColour(blip, 5) -- yellow: worth watching, not worth panicking about
        SetBlipScale(blip, 0.7)
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(site.name or 'Shop')
        EndTextCommandSetBlipName(blip)

        blips.sites[#blips.sites + 1] = blip
    end
end

local function drawTrack(status)
    if not status.track then
        for _, key in ipairs({ 'track', 'ring', 'search' }) do
            if blips[key] and DoesBlipExist(blips[key]) then RemoveBlip(blips[key]) end
            blips[key] = nil
        end
        blips.radius = 0
        return
    end

    if not blips.track or not DoesBlipExist(blips.track) then
        blips.track = AddBlipForCoord(status.track.x, status.track.y, status.track.z)
        SetBlipSprite(blips.track, 161)
        SetBlipColour(blips.track, 1)
        SetBlipScale(blips.track, 1.0)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('Suspect')
        EndTextCommandSetBlipName(blips.track)
    end

    SetBlipCoords(blips.track, status.track.x, status.track.y, status.track.z)
    SetBlipRoute(blips.track, true)
    SetBlipRouteColour(blips.track, 1)

    local hard = status.contact == 'hard'
    SetBlipFlashes(blips.track, hard)

    -- With eyes on, the dot IS the answer. Once it is a guess, all they get is
    -- which way he was going - and the arrow keeps pointing that way even
    -- after he has turned round, which is the entire joke.
    if hard then
        ShowHeadingIndicatorOnBlip(blips.track, false)
    elseif status.heading then
        SetBlipRotation(blips.track, math.floor(status.heading))
        ShowHeadingIndicatorOnBlip(blips.track, true)
    end

    -- A tight ring while somebody is actually looking at him, so a live lock
    -- never reads the same as a cold guess.
    if hard then
        if not blips.ring or not DoesBlipExist(blips.ring) then
            blips.ring = AddBlipForRadius(status.track.x, status.track.y, status.track.z, 45.0)
            SetBlipColour(blips.ring, 1)
            SetBlipAlpha(blips.ring, 110)
        else
            SetBlipCoords(blips.ring, status.track.x, status.track.y, status.track.z)
        end
    elseif blips.ring and DoesBlipExist(blips.ring) then
        RemoveBlip(blips.ring)
        blips.ring = nil
    end

    -- The search circle. Rebuilt rather than resized because a radius blip's
    -- size is fixed at creation; only when it has actually changed enough to
    -- see, or the map flickers.
    local radius = status.radius or 0.0

    if radius > 0.0 then
        if math.abs(radius - blips.radius) > 10.0
            or not blips.search or not DoesBlipExist(blips.search) then
            if blips.search and DoesBlipExist(blips.search) then RemoveBlip(blips.search) end

            blips.search = AddBlipForRadius(status.track.x, status.track.y, status.track.z, radius)
            SetBlipColour(blips.search, 1)
            SetBlipAlpha(blips.search, 80)
            blips.radius = radius
        else
            SetBlipCoords(blips.search, status.track.x, status.track.y, status.track.z)
        end
    elseif blips.search and DoesBlipExist(blips.search) then
        RemoveBlip(blips.search)
        blips.search = nil
        blips.radius = 0
    end
end

CreateThread(function()
    while true do
        Wait(500)

        local role, status = NickState()

        if role == 'police' and status.phase and status.phase ~= 'idle' then
            ensureSiteBlips()
            drawTrack(status)

            local kept = {}
            for _, ping in ipairs(blips.pings) do
                if GetGameTimer() < ping.expires then
                    kept[#kept + 1] = ping
                elseif DoesBlipExist(ping.blip) then
                    RemoveBlip(ping.blip)
                end
            end
            blips.pings = kept
        elseif blips.track or blips.search or #blips.sites > 0 or #blips.pings > 0 then
            clearBlips()
        end
    end
end)

-- Alarms and burned safehouses. A report you can miss may as well not exist,
-- so it lands with a noise as well as a blip.
RegisterNetEvent('nick:ping', function(kind, at, label)
    local role = NickState()
    if role ~= 'police' then return end

    local blip = AddBlipForCoord(at.x, at.y, at.z)
    SetBlipSprite(blip, 161)
    SetBlipColour(blip, kind == 'alarm' and 5 or 2)
    SetBlipScale(blip, 0.9)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label or 'Report')
    EndTextCommandSetBlipName(blip)

    blips.pings[#blips.pings + 1] = {
        blip    = blip,
        expires = GetGameTimer() + Config.escalation.PING_LIFE_MS,
    }

    NickHUD.notify(('~b~999:~w~ %s'):format(label or 'report received'))
    PlaySoundFrontend(-1, 'Event_Start_Text', 'GTAO_FM_Events_Soundset', true)
    PlayPoliceReport('CRIME_STOLEN_VEHICLE_01', 0.0)
end)

-- Control on the radio as the search warms and cools. Dry by design: morale
-- is not their department. Lines live in Config.flavour; the server already
-- keeps the robber off the distribution list, this check is just the belt.
RegisterNetEvent('nick:radio', function(line)
    local role = NickState()
    if role ~= 'police' then return end

    NickHUD.notify(('~b~Control:~w~ %s'):format(line))
end)

-- ===== kit, death, arrest =====
RegisterNetEvent('nick:role', function(role)
    pcall(function() exports.spawnmanager:setAutoSpawn(false) end)

    if role.isRobber then
        -- His round ends by arrest or by clock - but the non-lethal floor is
        -- enforced per frame and can be outrun (a petrol tank going up, a
        -- long swim), and a dead robber with respawn off would be ten
        -- minutes of everyone watching a corpse. So he gets up where he
        -- fell; the delay is the law's window to walk over and nick the
        -- body, and the bag survives because it only ever lived on the
        -- server.
        TriggerEvent('core:respawnPolicy', {
            kind        = 'where-you-fell',
            delay       = Config.nonLethal.DIED_RESPAWN_S,
            downMessage = '~r~That went badly.~w~ You are having a lie down.',
            upMessage   = '~y~Up. Somehow.~w~ The bag made it too.',
        })
        return
    end

    -- The kit is issued on 'nick:go', NOT here: main.lua is changing the
    -- player model behind the fade at this exact moment and a model swap
    -- takes every weapon with it. Chase issues on release for the same reason.

    -- A copper is never out of the round: wrecking a cruiser costs you the
    -- pursuit, not the evening.
    TriggerEvent('core:respawnPolicy', {
        kind        = 'where-you-fell',
        delay       = Config.police.RESPAWN_S,
        loadout     = Config.kit.POLICE_LOADOUT,
        downMessage = '~r~You\'re down.~w~ Back on shift shortly.',
        upMessage   = '~b~Back on shift.~w~ Get after him.',
    })
end)

RegisterNetEvent('nick:go', function()
    local role = NickState()
    if role ~= 'police' then return end

    ApplyLoadout(Config.kit.POLICE_LOADOUT)
end)

RegisterNetEvent('nick:end', function()
    pcall(function() exports.spawnmanager:setAutoSpawn(true) end)
    TriggerEvent('core:respawnPolicy', { kind = 'off' })
    clearBlips()
    fleet.sweep()
end)

-- Never out of ammunition. Running dry mid-pursuit just stalls the round; the
-- interesting constraint is catching him, not counting rounds. Topped up
-- rather than made infinite, so the reload still happens.
CreateThread(function()
    while true do
        Wait(2000)

        local role, status = NickState()

        if role == 'police' and status.phase and status.phase ~= 'idle' then
            local ped    = PlayerPedId()
            local weapon = GetHashKey('WEAPON_PISTOL')

            if HasPedGotWeapon(ped, weapon, false)
                and GetAmmoInPedWeapon(ped, weapon) < Config.kit.POLICE_AMMO then
                AddAmmoToPed(ped, weapon, Config.kit.POLICE_AMMO)
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(0)

        local role, status = NickState()

        if role == 'police' and status.phase == 'active' then
            local ped = robberPed(status)
            local me  = PlayerPedId()

            -- Dead is not a loophole: the floor can be outrun (see robber.lua)
            -- and a body that could not be nicked would soft-lock the round,
            -- so the prompt works on a corpse too. Nicking the body is also
            -- funnier.
            if ped and not IsPedInAnyVehicle(me, false) then
                local dist = #(GetEntityCoords(ped) - GetEntityCoords(me))

                if dist < Config.arrest.RANGE and GetEntitySpeed(ped) < Config.arrest.MAX_SPEED then
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName('~INPUT_PICKUP~ Nick him')
                    EndTextCommandDisplayHelp(0, false, false, -1)

                    if IsControlJustReleased(0, Config.controls.PRIMARY) then
                        TriggerServerEvent('nick:arrest')
                    end
                end
            end
        else
            Wait(500)
        end
    end
end)

-- ===== rubber banding =====
-- Help closing a GAP, never help winning a drag race. Distance is measured to
-- what DISPATCH says - the guess, not the truth - so the boost can never be
-- felt out like a radar, and while the trail is cold there is no boost at all.
--
-- Only the acceleration half of BAND_POWER_WEIGHT is wired up. The top-speed
-- natives disagree about their own units badly enough to hand a cruiser 200mph
-- by accident, and "no cop car catches him on straights alone" is an
-- acceptance criterion - so the safe half is the half we want anyway.
CreateThread(function()
    local applied = { vehicle = 0, value = -1.0 }

    while true do
        Wait(700)

        local role, status = NickState()
        local ped     = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local band    = Config.banding

        if role == 'police' and status.phase == 'active' and vehicle ~= 0 and status.track then
            local gap  = #(vector3(status.track.x, status.track.y, status.track.z) - GetEntityCoords(ped))
            local span = math.max(1.0, band.BAND_FULL_DISTANCE - band.BAND_START_DISTANCE)
            local howFar = math.min(1.0, math.max(0.0, (gap - band.BAND_START_DISTANCE) / span))

            -- The floor is a guard, not a brake: nothing here ever de-powers a
            -- police car, so a robber in a milk float can never be unshakeable.
            local mult  = math.max(band.POLICE_SPEED_FLOOR_PCT,
                1.0 + (band.BAND_MAX_MULTIPLIER - 1.0) * howFar)
            local value = (mult - 1.0) * 100.0 * band.BAND_POWER_WEIGHT

            if vehicle ~= applied.vehicle or math.abs(value - applied.value) > 1.0 then
                SetVehicleEnginePowerMultiplier(vehicle, value)
                applied = { vehicle = vehicle, value = value }
            end
        elseif applied.vehicle ~= 0 then
            -- Hand the engine back, or the boost follows the car into free roam.
            if DoesEntityExist(applied.vehicle) then
                SetVehicleEnginePowerMultiplier(applied.vehicle, 0.0)
            end
            applied = { vehicle = 0, value = -1.0 }
        end
    end
end)

-- ===== a replacement motor =====
-- The scope asks for a cop to come back "at the nearest road with a
-- replacement vehicle". Standing in a field watching a pursuit you can hear is
-- not a round, so if a copper has been on foot with nothing drivable near them
-- for a moment, one turns up on the nearest road.
CreateThread(function()
    local onFootSince = 0

    while true do
        Wait(2000)

        local role, status = NickState()
        local ped = PlayerPedId()

        if role == 'police' and status.phase == 'active'
            and not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) then
            local me     = GetEntityCoords(ped)
            local nearby = false

            for _, vehicle in ipairs(GetGamePool('CVehicle')) do
                if DoesEntityExist(vehicle) and not IsEntityDead(vehicle)
                    and IsVehicleSeatFree(vehicle, -1)
                    and #(GetEntityCoords(vehicle) - me) < 30.0 then
                    nearby = true
                    break
                end
            end

            if nearby then
                onFootSince = 0
            else
                if onFootSince == 0 then onFootSince = GetGameTimer() end

                if GetGameTimer() - onFootSince > 10000 then
                    onFootSince = 0

                    local ok, node, heading = GetClosestVehicleNodeWithHeading(
                        me.x, me.y, me.z, 1, 3.0, 0)

                    local hash = SBM.loadModel(
                        Config.vehicles.POLICE[math.random(#Config.vehicles.POLICE)])

                    if ok and hash then
                        local car = CreateVehicle(hash, node.x, node.y, node.z + 0.5, heading, true, true)
                        SetModelAsNoLongerNeeded(hash)

                        if DoesEntityExist(car) then
                            SetVehicleOnGroundProperly(car)
                            SetVehicleEngineOn(car, true, true, false)
                            SetVehicleDoorsLocked(car, 1)
                            fleet.track(car)
                            NickHUD.notify('~b~Relief car dropped off~w~ - it is on the road behind you.')
                        end
                    end
                end
            end
        else
            onFootSince = 0
        end
    end
end)

-- ===== your colleagues, and the blues and twos =====
-- Traffic pulling aside for a siren is behaviour GTA already has; it just
-- needs the siren actually on. The mate blips matter because a mode that
-- claims the world turns free roam's radar off with it, and a copper who can
-- see the suspect but not a single colleague cannot coordinate anything.
CreateThread(function()
    local mates, siren = {}, 0

    while true do
        Wait(1000)

        local role, status = NickState()
        local onDuty = role == 'police' and status.phase and status.phase ~= 'idle'

        for _, id in ipairs(GetActivePlayers()) do
            local server = GetPlayerServerId(id)
            local ped    = GetPlayerPed(id)
            local wanted = onDuty and id ~= PlayerId()
                and server ~= status.robberId and DoesEntityExist(ped)

            if wanted and not (mates[server] and DoesBlipExist(mates[server])) then
                local blip = AddBlipForEntity(ped)
                SetBlipSprite(blip, 1)
                SetBlipColour(blip, 3) -- blue
                SetBlipScale(blip, 0.75)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString(GetPlayerName(id))
                EndTextCommandSetBlipName(blip)
                mates[server] = blip
            elseif not wanted and mates[server] and DoesBlipExist(mates[server]) then
                RemoveBlip(mates[server])
                mates[server] = nil
            end
        end

        local ped     = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if onDuty and vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
            siren = vehicle
            SetVehicleSiren(vehicle, true)
            SetVehicleHasMutedSirens(vehicle, false)
        elseif siren ~= 0 then
            if DoesEntityExist(siren) then SetVehicleSiren(siren, false) end
            siren = 0
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearBlips()
    fleet.sweep()
end)
