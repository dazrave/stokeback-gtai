-- The police brain: eyes, the map, the arrest, and the one bit of help the
-- law gets on a straight road.
--
-- The eyes are chase's, because chase already paid for the two mistakes in
-- them: trace CAR to CAR rather than ped to ped (the line-of-sight test only
-- ignores the two entities you name, so two people in cars have four bits of
-- bodywork between them and a bumper-to-bumper pursuit never counts as a
-- sighting), and check the screen as well as the distance.
local blips = { track = nil, ring = nil, search = nil, radius = 0, sites = {}, burned = {}, pings = {} }
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
    for _, blip in pairs(blips.burned) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    for _, ping in ipairs(blips.pings) do
        if DoesBlipExist(ping.blip) then RemoveBlip(ping.blip) end
    end

    blips = { track = nil, ring = nil, search = nil, radius = 0, sites = {}, burned = {}, pings = {} }
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

-- Reveal on use (plan §4.4). A safehouse he has banked at is burned for the
-- rest of the round - not a ping that fades, a fixture on their map. It is
-- what forces him to rotate, and what turns the last two minutes into a set of
-- known doors the police can sit on.
local function ensureBurnedBlips(status)
    for _, house in ipairs(status.burned or {}) do
        local key = ('%d:%d'):format(math.floor(house.x), math.floor(house.y))

        if not (blips.burned[key] and DoesBlipExist(blips.burned[key])) then
            local blip = AddBlipForCoord(house.x, house.y, house.z)
            SetBlipSprite(blip, 1)
            SetBlipColour(blip, 2) -- green: a door he has already used
            SetBlipScale(blip, 0.85)
            SetBlipAsShortRange(blip, false)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(('Known stash - %s'):format(house.name or 'doorway'))
            EndTextCommandSetBlipName(blip)

            blips.burned[key] = blip
            NickHUD.notify('~g~That doorway is on your map now.~w~ He has to find another one.')
        end
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

    -- The GPS line is NOT set here. client/gps.lua owns every route in this
    -- mode, because the best thing to drive at is often not the suspect - it
    -- is a sounding alarm, or a witness call, or the shop he has not hit yet -
    -- and two files both setting routes would fight over the minimap.

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
            ensureBurnedBlips(status)
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
        elseif blips.track or blips.search or #blips.sites > 0 or #blips.pings > 0
            or next(blips.burned) then
            clearBlips()
        end
    end
end)

-- Alarms and burned safehouses. A report you can miss may as well not exist,
-- so it lands with a noise as well as a blip.
RegisterNetEvent('nick:ping', function(kind, at, label)
    local role = NickState()
    if role ~= 'police' then return end

    local COLOURS = { alarm = 5, stash = 2, witness = 3 } -- yellow, green, blue

    local blip = AddBlipForCoord(at.x, at.y, at.z)
    SetBlipSprite(blip, 161)
    SetBlipColour(blip, COLOURS[kind] or 5)
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

-- The arrest, and the rung of the ladder just below it: hauling him out of a
-- slowing car. Both are prompts on a copper who is ON FOOT, which is what
-- makes the escalation ladder physical - you have to get out and walk over.
CreateThread(function()
    local clingMs = 0

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
                local theirs = GetVehiclePedIsIn(ped, false)
                local dist   = #(GetEntityCoords(ped) - GetEntityCoords(me))

                if theirs ~= 0 then
                    -- JACK, NEVER ENTER (plan §5.2). Note what this does NOT
                    -- do: give this copper an enter-vehicle task. He is never
                    -- offered the seat, so he can never end up driving off in
                    -- the getaway car - the failure mode that would turn the
                    -- best rung of the ladder into a farce.
                    local slow = GetEntitySpeed(theirs) < Config.jack.MAX_SPEED
                    local near = #(GetEntityCoords(theirs) - GetEntityCoords(me)) < Config.jack.RADIUS

                    if slow and near then
                        BeginTextCommandDisplayHelp('STRING')
                        AddTextComponentSubstringPlayerName('~INPUT_PICKUP~ Get him out of there')
                        EndTextCommandDisplayHelp(0, false, false, -1)

                        if IsControlPressed(0, Config.controls.PRIMARY) then
                            clingMs = clingMs + GetFrameTime() * 1000

                            if clingMs >= Config.jack.HOLD_MS then
                                clingMs = 0
                                TriggerServerEvent('nick:jack')
                            end
                        else
                            clingMs = 0
                        end
                    else
                        clingMs = 0
                    end

                elseif dist < Config.arrest.RANGE and GetEntitySpeed(ped) < Config.arrest.MAX_SPEED then
                    clingMs = 0

                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName('~INPUT_PICKUP~ Nick him')
                    EndTextCommandDisplayHelp(0, false, false, -1)

                    if IsControlJustReleased(0, Config.controls.PRIMARY) then
                        TriggerServerEvent('nick:arrest')
                    end
                else
                    clingMs = 0
                end
            end
        else
            clingMs = 0
            Wait(500)
        end
    end
end)

-- Our half of the pull-out. The server only ever sends this to the copper who
-- earned it, and it is animation and nothing else - the task that matters
-- runs on the robber's own machine, which is the machine that owns his ped.
RegisterNetEvent('nick:jackAnim', function()
    local role = NickState()
    if role ~= 'police' then return end

    NickAnim(Config.jack.ANIM_DICT, Config.jack.ANIM_COP, Config.jack.ANIM_MS)
    NickHUD.notify('~b~Out you come.')
end)

-- ===== calling the favour in =====
-- One press, team-wide, one use. The button only exists while the team's
-- contact score says they have genuinely lost him - it answers an INFORMATION
-- deficit, which is why it must never be available at the same time as the
-- rubber band, which answers a distance one (plan §5.3).
CreateThread(function()
    while true do
        Wait(200)

        local role, status = NickState()

        if role == 'police' and status.phase == 'active' and NickPolice().heliReady then
            if IsControlJustReleased(0, Config.controls.SECONDARY) then
                TriggerServerEvent('nick:heliCall')
            end
        end
    end
end)

-- ===== the piloted air unit =====
-- Darren, game night: "I thought we could spawn and pilot our own Heli?" -
-- now you can. /heli asks control; if the ration book allows it, a bird
-- lands on the pad for whoever goes and gets it. It carries no magic: the
-- air's only edge is SIGHT_AIR_RANGE through the same LOS rule as the
-- ground, and the robber gets a proximity icon in exchange (robber.lua).
RegisterCommand((Config.airUnit and Config.airUnit.COMMAND) or 'heli', function()
    local role, status = NickState()

    if role ~= 'police' or status.phase ~= 'active' then
        return NickHUD.notify('~y~No round on, or flying is not your department.')
    end

    TriggerServerEvent('nick:airUnit')
end, false)

-- The approval, back to whoever asked. The helicopter is NOT spawned until
-- its collector is nearly at the pad: OneSync treats an entity created a
-- long way from its creator as a rumour, and a rumour with rotors is how you
-- lose an aircraft before anyone has sat in it.
RegisterNetEvent('nick:airUnitGo', function(pad)
    local role = NickState()
    if role ~= 'police' or not pad then return end

    NickHUD.notify(('~b~Air unit approved.~w~ She lands on the pad at %s - go and get her.')
        :format(pad.name or 'the pad'))

    CreateThread(function()
        local deadline = GetGameTimer() + 240000 -- takes too long and the offer lapses

        while GetGameTimer() < deadline do
            Wait(1000)

            local role2, status = NickState()
            if role2 ~= 'police' or status.phase ~= 'active' then return end

            if #(GetEntityCoords(PlayerPedId()) - vector3(pad.x, pad.y, pad.z))
                < ((Config.airUnit and Config.airUnit.SPAWN_WITHIN) or 200.0) then
                local hash = SBM.loadModel((Config.airUnit and Config.airUnit.MODEL) or 'polmav')
                if not hash then return end

                RequestCollisionAtCoord(pad.x, pad.y, pad.z)

                local heli = CreateVehicle(hash, pad.x, pad.y, pad.z + 1.0, pad.h or 0.0, true, true)
                SetModelAsNoLongerNeeded(hash)
                if not DoesEntityExist(heli) then return end

                SetVehicleOnGroundProperly(heli)
                fleet.track(heli)   -- swept with the cruisers at the whistle
                NickReportCar(heli) -- and by the server if this client vanishes

                NickHUD.notify('~b~She is on the pad.~w~ Mind the wires.')
                return
            end
        end
    end)
end)

-- OneSync culls distant players out of existence client-side, which would make
-- a helicopter's whole job impossible - it would be flying over an empty city.
-- The server hands airborne police a bigger bubble; this is the only thing
-- that knows when to ask for one.
CreateThread(function()
    local airborne = false

    while true do
        Wait(2000)

        local role, status = NickState()
        local live = role == 'police' and status.phase and status.phase ~= 'idle'
        local ped  = PlayerPedId()

        local up = live and IsPedInAnyVehicle(ped, false) and IsPedInFlyingVehicle(ped)

        if up ~= airborne then
            airborne = up
            TriggerServerEvent('nick:airborne', up and true or false)
        end
    end
end)

-- ===== rubber banding =====
-- Help closing a GAP, never help winning a drag race. Distance is measured to
-- what DISPATCH says - the guess, not the truth - so the boost can never be
-- felt out like a radar. The gate is status.track, which exists for a hard
-- lock AND for the drifting search circle: a warm circle is still a chase.
-- Only fully cold starves the band, by design.
--
-- Only the acceleration half of BAND_POWER_WEIGHT is wired up. The top-speed
-- natives disagree about their own units badly enough to hand a cruiser 200mph
-- by accident, and "no cop car catches him on straights alone" is an
-- acceptance criterion - so the safe half is the half we want anyway.
--
-- THE PER-FRAME TRAP (the SetBlipRoute lesson, in vehicle form): the power
-- native is a per-frame EFFECT - set once, it lasts one frame and does
-- nothing a driver can feel. The first cut applied it only when the value
-- CHANGED, on a 700ms clock, so the band never worked at all ("robber was
-- absolutely running away on the straights"). The sums stay on the slow
-- clock here; the APPLICATION is the per-frame thread underneath.
local bandPower = { vehicle = 0, value = 0.0 }

CreateThread(function()
    local capped = 0 -- the vehicle currently wearing the close-range cap

    -- Engagement is reported to the server on state CHANGES only, throttled,
    -- so "was the rubber band working?" is answerable from the log instead of
    -- from vibes at the bar afterwards.
    local engaged, logAt = false, 0

    local function report(nowEngaged, value)
        if nowEngaged == engaged then return end
        if nowEngaged and GetGameTimer() < logAt then return end -- engages throttled; drops always land
        engaged, logAt = nowEngaged, GetGameTimer() + 3000
        TriggerServerEvent('nick:bandState', nowEngaged, value)
    end

    local function handBack()
        bandPower = { vehicle = 0, value = 0.0 } -- per-frame: stopping is the reset

        if capped ~= 0 and DoesEntityExist(capped) then
            SetVehicleMaxSpeed(capped, 0.0) -- 0 = its own engine back
        end
        capped = 0
    end

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

            bandPower = { vehicle = vehicle, value = value }
            report(value > 0.5, value)

            -- INSIDE the band start, the help stops and a CAP begins (plan
            -- §5.1): close up, a police car may not go faster than the car it
            -- is chasing, so the last two hundred metres are decided by
            -- cornering, a cutoff or a burst tyre and never by horsepower -
            -- which is acceptance test 3, written as a native.
            --
            -- The floor is what keeps that honest in the other direction: the
            -- cap can never drop a cruiser below POLICE_SPEED_FLOOR_PCT of its
            -- own top speed, so a robber deliberately dawdling in something
            -- slow cannot drag the entire force down to walking pace with him
            -- (acceptance test 6).
            local theirs = robberPed(status)
            local theirVehicle = theirs and GetVehiclePedIsIn(theirs, false) or 0

            if gap < band.BAND_START_DISTANCE and theirVehicle ~= 0 then
                local mineTop  = GetVehicleEstimatedMaxSpeed(vehicle)
                local theirTop = GetVehicleEstimatedMaxSpeed(theirVehicle)

                if mineTop > 0.0 and theirTop > 0.0 then
                    SetVehicleMaxSpeed(vehicle, math.max(theirTop, mineTop * band.POLICE_SPEED_FLOOR_PCT))
                    capped = vehicle
                end
            elseif capped ~= 0 then
                if DoesEntityExist(capped) then SetVehicleMaxSpeed(capped, 0.0) end
                capped = 0
            end
        elseif bandPower.vehicle ~= 0 or capped ~= 0 then
            -- Hand the engine back, or the boost and the cap both follow the
            -- car into free roam.
            handBack()
            report(false, 0.0)
        end
    end
end)

-- The application half: per frame, or it is not an effect at all. Nothing is
-- computed here - the slow thread above decides, this one merely keeps saying
-- it. Letting go IS the reset, which is the one kindness of a per-frame
-- native: it cannot leak into free roam.
CreateThread(function()
    while true do
        Wait(0)

        if bandPower.vehicle ~= 0 and bandPower.value > 0.0
            and DoesEntityExist(bandPower.vehicle) then
            SetVehicleEnginePowerMultiplier(bandPower.vehicle, bandPower.value)
        else
            Wait(250)
        end
    end
end)

-- ===== a replacement motor =====
-- Two ways a copper ends up stranded, one answer. Wrecking your car has to
-- cost you the pursuit and not your evening: standing in a field listening to
-- a chase you can hear and cannot reach is the fastest way to lose a player
-- for ten minutes.
local function dropRelief(at, announce)
    local ok, node, heading = GetClosestVehicleNodeWithHeading(at.x, at.y, at.z, 1, 3.0, 0)
    if not ok then return nil end

    local hash = SBM.loadModel(Config.vehicles.POLICE[math.random(#Config.vehicles.POLICE)])
    if not hash then return nil end

    local car = CreateVehicle(hash, node.x, node.y, node.z + 0.5, heading, true, true)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(car) then return nil end

    SetVehicleOnGroundProperly(car)
    SetVehicleEngineOn(car, true, true, false)
    SetVehicleDoorsLocked(car, 1) -- 1 = unlocked; a locked relief car is a cruel joke
    fleet.track(car)
    NickReportCar(car) -- and the server's sweep, should this client vanish mid-round

    if announce then NickHUD.notify(announce) end
    return car, node
end

-- Back on shift: core's respawn policy stands you up where you fell, and this
-- moves you to the nearest ROAD with a fresh vehicle (plan §7, phase 3).
-- Watched as a death->alive transition rather than hooked, because the policy
-- lives in core and a mode should not be reaching into its resurrect.
CreateThread(function()
    local wasDead = false

    while true do
        Wait(500)

        local role, status = NickState()
        local ped  = PlayerPedId()
        local dead = IsEntityDead(ped) or IsPedFatallyInjured(ped)

        if role ~= 'police' or not status.phase or status.phase == 'idle' then
            wasDead = false
        elseif dead then
            wasDead = true
        elseif wasDead then
            wasDead = false

            if Config.police.RESPAWN_TO_ROAD then
                -- Behind a fade, because a teleport plus a car appearing next
                -- to you reads as a glitch at full brightness and as a lift
                -- from control in the dark.
                SBM.behindFade(function()
                    local me = GetEntityCoords(ped)
                    local car, node = dropRelief(me, nil)

                    if node then
                        SetEntityCoords(PlayerPedId(), node.x, node.y, node.z + 1.0,
                            false, false, false, false)
                    end

                    if car and Config.police.RESPAWN_WITH_CAR and DoesEntityExist(car) then
                        TaskWarpPedIntoVehicle(PlayerPedId(), car, -1)
                    end
                end)

                NickHUD.notify('~b~Fresh motor, fresh start.~w~ Try not to.')
            end
        end
    end
end)

-- The other stranding: you survived, your cruiser did not. Nothing drivable
-- near you for a moment and one turns up on the nearest road.
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
                    and #(GetEntityCoords(vehicle) - me) < Config.police.RELIEF_RADIUS then
                    nearby = true
                    break
                end
            end

            if nearby then
                onFootSince = 0
            else
                if onFootSince == 0 then onFootSince = GetGameTimer() end

                if GetGameTimer() - onFootSince > Config.police.RELIEF_AFTER_S * 1000 then
                    onFootSince = 0
                    dropRelief(me, '~b~Relief car dropped off~w~ - it is on the road behind you.')
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
