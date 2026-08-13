-- Position sampler: one fix every few seconds, shipped to the server in small
-- batches. Cheap enough to forget it exists.
local SAMPLE_MS  = 3000
local BATCH_SIZE = 7

local buffer = {}

CreateThread(function()
    while true do
        Wait(SAMPLE_MS)

        if NetworkIsPlayerActive(PlayerId()) then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)

            buffer[#buffer + 1] = {
                x = math.floor(pos.x * 10) / 10,
                y = math.floor(pos.y * 10) / 10,
                z = math.floor(pos.z * 10) / 10,
                s = math.floor(GetEntitySpeed(ped) * 10) / 10, -- m/s
                v = IsPedInAnyVehicle(ped, false) and 1 or 0,
                d = IsEntityDead(ped) and 1 or 0,
            }

            if #buffer >= BATCH_SIZE then
                TriggerServerEvent('telemetry:batch', buffer)
                buffer = {}
            end
        end
    end
end)

-- ===== clapperboard flash =====
-- A sync point the camera can see. When the server fires a clap, the whole
-- screen goes white for a beat (visible in every OBS capture) and a beep plays
-- (useful where game audio is recorded). Editors line the flashes up to sync
-- every angle to the same instant.
local flashUntil = 0

CreateThread(function()
    while true do
        if GetGameTimer() < flashUntil then
            DrawRect(0.5, 0.5, 1.0, 1.0, 255, 255, 255, 255)
            Wait(0)
        else
            Wait(80)
        end
    end
end)

RegisterNetEvent('telemetry:sync', function(n)
    flashUntil = GetGameTimer() + 130 -- ~a tenth of a second of pure white
    PlaySoundFrontend(-1, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)

    SBM.notify(('~y~CLAP #%d~w~ — synced'):format(n or 0))
end)

-- Part of /resetgame: everyone gets a clean respawn at a normal map spawn.
RegisterNetEvent('telemetry:respawn', function(at, index)
    DoScreenFadeOut(400)
    Wait(500)

    exports.spawnmanager:setAutoSpawn(true)

    if at then
        -- Fan out around the shared point so three people don't land inside
        -- each other, but stay close enough to see who you're with.
        local angle = ((index or 1) - 1) * 1.7

        exports.spawnmanager:spawnPlayer({
            x        = at.x + math.cos(angle) * 4.5,
            y        = at.y + math.sin(angle) * 4.5,
            z        = at.z,
            heading  = at.h or 0.0,
            model    = GetEntityModel(PlayerPedId()),
            skipFade = true,
        })

        -- Settle onto the ground once collision has streamed in.
        Wait(900)
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 30.0, false)
        if found then
            SetEntityCoords(ped, pos.x, pos.y, groundZ + 1.0, false, false, false, false)
        end
    else
        exports.spawnmanager:spawnPlayer()
        Wait(900)
    end

    DoScreenFadeIn(600)
end)

-- ===== mate radar =====
-- In free roam (no mission, no horde, no chase round) every human shows as a
-- dot on the map. Positions are relayed through the server so mates show up
-- at ANY distance, not just network scope.
local mates    = {}
local blips    = {}
local engaged  = false
local inChase  = false

RegisterNetEvent('infected:engaged', function(on) engaged = on and true or false end)
RegisterNetEvent('chase:role', function() inChase = true end)
RegisterNetEvent('chase:end', function() inChase = false end)

-- ===== free-roam perks =====
-- Unlimited ammo while nothing is being scored. The server's flag covers
-- every registered gametype plus pint; engaged/inChase are kept in the gate
-- anyway because they arrive instantly while the flag ticks at 3s - a horde
-- must never start against a player still on bottomless clips. Reapplied
-- every tick so a respawned ped inherits the current state.
local freeroam = false
RegisterNetEvent('telemetry:freeroam', function(on) freeroam = on and true or false end)

CreateThread(function()
    while true do
        SetPedInfiniteAmmoClip(PlayerPedId(), freeroam and not engaged and not inChase)
        Wait(1000)
    end
end)

-- How often your position leaves this machine. The map is only ever as fresh
-- as the slowest link in send -> relay -> redraw, and at 4s each that was up
-- to ten seconds of lag: a mate's dot sat a street behind where they actually
-- were, which is useless for finding each other.
local PING_MS = 1000

CreateThread(function()
    while true do
        Wait(PING_MS)

        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        TriggerServerEvent('telemetry:ping', snapshot(ped, pos))
    end
end)

-- ===== what an issue needs to make sense later =====
-- "the zombies are too fast" means different things on foot with two shells
-- left than it does in a car at the observatory. An overheard line is only
-- useful with the situation attached, so every ping carries the situation.

-- Hashes are what the natives hand back; these are the ones this project
-- actually uses, so the issue reads "pump shotgun" not "-1878508229".
local WEAPON_NAMES = {}
for name, label in pairs({
    WEAPON_UNARMED = 'fists',        WEAPON_PISTOL      = 'pistol',
    WEAPON_COMBATPISTOL = 'combat pistol',
    WEAPON_PUMPSHOTGUN = 'pump shotgun', WEAPON_SAWNOFFSHOTGUN = 'sawn-off',
    WEAPON_MICROSMG = 'micro SMG',    WEAPON_SMG        = 'SMG',
    WEAPON_ASSAULTRIFLE = 'assault rifle', WEAPON_CARBINERIFLE = 'carbine',
    WEAPON_BAT = 'bat',               WEAPON_CROWBAR    = 'crowbar',
    WEAPON_KNIFE = 'knife',           WEAPON_MACHETE    = 'machete',
    WEAPON_GRENADE = 'grenade',       WEAPON_MOLOTOV    = 'molotov',
    WEAPON_PETROLCAN = 'petrol can',  WEAPON_FLASHLIGHT = 'torch',
}) do
    WEAPON_NAMES[GetHashKey(name)] = label
end

local function weaponInfo(ped)
    local hash = GetSelectedPedWeapon(ped)
    local name = WEAPON_NAMES[hash] or ('hash ' .. tostring(hash))
    -- Ammo excludes the loaded clip on some weapons; total is what a player
    -- means when they say "I'm out".
    local _, ammo = GetAmmoInClip(ped, hash)
    return name, (GetAmmoInPedWeapon(ped, hash) or 0), (ammo or 0)
end

local function snapshot(ped, pos)
    local weapon, ammo, clip = weaponInfo(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)

    return {
        x = pos.x, y = pos.y, z = pos.z,
        v = vehicle ~= 0,
        d = IsEntityDead(ped),

        -- Where, in words a person would use.
        street = GetStreetNameFromHashKey(GetStreetNameAtCoord(pos.x, pos.y, pos.z)),
        area   = GetLabelText(GetNameOfZone(pos.x, pos.y, pos.z)),

        -- What they were holding and whether they were out.
        weapon = weapon,
        ammo   = ammo,
        clip   = clip,

        -- What state they were in.
        hp     = GetEntityHealth(ped),
        armour = GetPedArmour(ped),
        skin   = GetEntityModel(ped),

        -- What they were driving, if anything.
        car    = vehicle ~= 0 and GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)) or nil,
        speed  = math.floor(GetEntitySpeed(ped) * 2.237),  -- mph, as spoken
    }
end

RegisterNetEvent('telemetry:mates', function(list)
    mates = list or {}
end)

-- Blip redraw. Faster than the relay would just redraw the same numbers.
local BLIP_MS = 1000

CreateThread(function()
    while true do
        Wait(BLIP_MS)

        local me   = GetPlayerServerId(PlayerId())
        local show = not engaged and not inChase
        local seen = {}

        if show then
            for _, mate in ipairs(mates) do
                if mate.id ~= me then
                    seen[mate.id] = true

                    if not blips[mate.id] or not DoesBlipExist(blips[mate.id]) then
                        local blip = AddBlipForCoord(mate.x, mate.y, mate.z)
                        SetBlipSprite(blip, 1)
                        SetBlipColour(blip, 3)
                        SetBlipScale(blip, 0.85)
                        BeginTextCommandSetBlipName('STRING')
                        AddTextComponentString(mate.name or 'Mate')
                        EndTextCommandSetBlipName(blip)
                        blips[mate.id] = blip
                    end

                    SetBlipCoords(blips[mate.id], mate.x, mate.y, mate.z)
                end
            end
        end

        for id, blip in pairs(blips) do
            if not seen[id] then
                if DoesBlipExist(blip) then RemoveBlip(blip) end
                blips[id] = nil
            end
        end
    end
end)

-- Part of /resetgame: bin every empty vehicle nearby, which clears mission
-- wrecks, spawned bangers and anything orphaned by an earlier session.
-- Ambient traffic repopulates on its own within seconds.
RegisterNetEvent('telemetry:clearworld', function()
    local cleared = 0

    -- Bodies first: corpses at mission points were surviving every restart.
    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            NetworkRequestControlOfEntity(ped)
            SetEntityAsMissionEntity(ped, true, true)
            DeleteEntity(ped)
            cleared = cleared + 1
        end
    end

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle)
            and IsVehicleSeatFree(vehicle, -1)
            and GetVehicleNumberOfPassengers(vehicle) == 0 then
            NetworkRequestControlOfEntity(vehicle)
            SetEntityAsMissionEntity(vehicle, true, true)
            DeleteEntity(vehicle)
            cleared = cleared + 1
        end
    end

    print(('[telemetry] cleared %d empty vehicles'):format(cleared))
end)

-- Who's on. Top-left, always, so you know who you're playing with without
-- opening the pause menu.
CreateThread(function()
    while true do
        Wait(0)

        local me = GetPlayerServerId(PlayerId())
        local y  = 0.020

        SetTextFont(4)
        SetTextScale(0.30, 0.30)
        SetTextColour(255, 220, 120, 220)
        SetTextOutline()
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName('~y~STOKEBACK MOUNTAIN')
        EndTextCommandDisplayText(0.015, y)

        y = y + 0.024

        for _, mate in ipairs(mates) do
            SetTextFont(4)
            SetTextScale(0.28, 0.28)
            SetTextColour(255, 255, 255, 200)
            SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(
                (mate.id == me and '~g~' or '~w~') .. (mate.name or '?'))
            EndTextCommandDisplayText(0.015, y)

            y = y + 0.022
        end
    end
end)


-- ===== spawn together =====
-- Ask the server to put us next to somebody, in free roam only. The server
-- decides, because only it knows where everyone is and which modes are live.
AddEventHandler('playerSpawned', function()
    CreateThread(function()
        -- Let everyone's position ping land before asking, or we'd be sent to
        -- wherever the group was a minute ago.
        Wait(2500)
        TriggerServerEvent('telemetry:needSpawnBuddy')
    end)
end)

RegisterNetEvent('telemetry:spawnNear', function(at)
    if not at or type(at.x) ~= 'number' then return end

    SBM.behindFade(function()
        local ped   = PlayerPedId()
        local angle = math.random() * 6.28

        -- A few metres off, so two people respawning together don't land inside
        -- one another.
        SetEntityCoords(ped, at.x + math.cos(angle) * 3.5,
                             at.y + math.sin(angle) * 3.5,
                             at.z + 1.0, false, false, false, false)

        -- One ground probe after a teleport fails, because the map hasn't streamed
        -- in yet - which is how you end up standing in the sky. Keep asking.
        for _ = 1, 25 do
            Wait(150)
            local pos = GetEntityCoords(ped)
            local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 30.0, false)
            if found then
                SetEntityCoords(ped, pos.x, pos.y, groundZ + 1.0, false, false, false, false)
                break
            end
        end
    end, 300, 500)

    SBM.notify(('~g~Dropped in near ~w~%s'):format(at.name or 'the crew'))
end)


-- ===== nobody stays dead in free roam =====
-- Auto-spawn is a single global switch that any mode can turn off, and every
-- mode that does has to remember to turn it back on down every exit path -
-- including the ones where it is stopped outright rather than ending cleanly.
-- That has failed at least once, and the symptom is the worst kind: you lie on
-- the floor watching everyone else play, with nothing on screen to explain it.
--
-- So this is a backstop, not the mechanism. It only acts in free roam, and only
-- after long enough that a mode's own revive or respawn has clearly not come.
local DEAD_FOR_TOO_LONG_MS = 12000

CreateThread(function()
    local deadSince = 0

    while true do
        Wait(1000)

        local ped = PlayerPedId()

        if not IsEntityDead(ped) then
            deadSince = 0
        elseif engaged or inChase then
            -- A mode owns the body: pint revives, chase respawns its own cops.
            deadSince = 0
        else
            if deadSince == 0 then
                deadSince = GetGameTimer()
            elseif GetGameTimer() - deadSince > DEAD_FOR_TOO_LONG_MS then
                deadSince = 0
                exports.spawnmanager:setAutoSpawn(true)
                exports.spawnmanager:forceRespawn()
            end
        end
    end
end)
