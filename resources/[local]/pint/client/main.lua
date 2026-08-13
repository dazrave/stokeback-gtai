-- Stage tracking, zones, blips, garrisons, respawn-at-checkpoint and mission
-- lifecycle. Which mission is running comes from the server with every
-- begin/stage event.
local state = {
    active           = false,
    mission          = nil,
    stageIndex       = 0,
    blip             = nil,
    checkpoint       = nil,
    lastZonePing     = 0,
    zoneTicks        = 0,
    claimedGarrisons = {},
}

local function setState(next)
    local merged = {}
    for key, value in pairs(state) do merged[key] = value end
    for key, value in pairs(next) do merged[key] = value end
    state = merged
end

local function M()
    return state.mission and Config.missions[state.mission] or nil
end

local function currentStage()
    local mission = M()
    return (state.active and mission) and mission.stages[state.stageIndex] or nil
end

local function clearBlip()
    if state.blip and DoesBlipExist(state.blip) then
        RemoveBlip(state.blip)
    end
end

local function setStageBlip(target)
    clearBlip()

    local blip = AddBlipForCoord(target.x, target.y, target.z)
    SetBlipSprite(blip, 1)
    SetBlipColour(blip, 5)
    SetBlipScale(blip, 0.9)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Objective')
    EndTextCommandSetBlipName(blip)

    return blip
end

local function formatDistance(metres)
    if metres >= 1000 then
        return ('%.1fkm'):format(metres / 1000)
    end
    return ('%dm'):format(math.floor(metres))
end

-- ===== death & spectate =====
-- During a mission, death is death: no checkpoint respawn. You spectate the
-- survivors until the last one falls; then the server wipes and restarts the
-- mission from the top.
local spectate = { on = false, reported = false, targetId = nil, gone = false }
local downed   = { list = {}, blips = {} }

local function stopSpectate()
    if spectate.on then
        NetworkSetInSpectatorMode(false, PlayerPedId())
    end
    spectate = { on = false, reported = false, targetId = nil, gone = false }
end

RegisterNetEvent('pint:downState', function(list)
    downed.list = list or {}

    local seen = {}
    for _, entry in ipairs(downed.list) do
        seen[entry.id] = true

        if not downed.blips[entry.id] or not DoesBlipExist(downed.blips[entry.id]) then
            local blip = AddBlipForCoord(entry.x, entry.y, entry.z)
            SetBlipSprite(blip, 153)
            SetBlipColour(blip, 1)
            SetBlipScale(blip, 1.0)
            SetBlipFlashes(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(entry.name .. ' - DOWN')
            EndTextCommandSetBlipName(blip)
            downed.blips[entry.id] = blip
        end
    end

    for id, blip in pairs(downed.blips) do
        if not seen[id] then
            if DoesBlipExist(blip) then RemoveBlip(blip) end
            downed.blips[id] = nil
        end
    end
end)

RegisterNetEvent('pint:revived', function(at)
    stopSpectate()

    -- Resurrect in place rather than respawn: the body stays where it fell,
    -- and a brief ragdoll on landing makes the game play its own get-up
    -- animation, so you climb to your feet instead of blinking upright.
    local ped = PlayerPedId()
    NetworkResurrectLocalPlayer(at.x, at.y, at.z + 0.4, GetEntityHeading(ped), true, false)

    ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    SetPedToRagdoll(ped, 900, 900, 0, false, false, false)

    Wait(1200)
    GiveWeaponToPed(PlayerPedId(), GetHashKey(Config.player.weapon),
        Config.player.ammoStart, false, true)

    PintHUD.notify('~g~Back up.~w~ Don\'t waste it.')
end)

RegisterNetEvent('pint:gone', function()
    spectate.gone = true
    PintHUD.notify('~r~That\'s it.~w~ Spectating the survivors...')
end)

-- Death reporting and, once the clock has run out, spectating.
CreateThread(function()
    while true do
        Wait(1000)

        if state.active and IsEntityDead(PlayerPedId()) then
            if not spectate.reported then
                local pos = GetEntityCoords(PlayerPedId())
                spectate = { on = false, reported = true, targetId = nil, gone = false }
                TriggerServerEvent('pint:died', { x = pos.x, y = pos.y, z = pos.z })
                PintHUD.notify(('~o~You\'re DOWN.~w~ A mate has %ds to reach you.'):format(
                    Config.reviveSeconds))
            end

            if spectate.gone then
                local target = nil
                for _, playerId in ipairs(GetActivePlayers()) do
                    if playerId ~= PlayerId() then
                        local ped = GetPlayerPed(playerId)
                        if DoesEntityExist(ped) and not IsEntityDead(ped) then
                            target = playerId
                            break
                        end
                    end
                end

                if target and (not spectate.on or spectate.targetId ~= target) then
                    NetworkSetInSpectatorMode(true, GetPlayerPed(target))
                    spectate = { on = true, reported = true, targetId = target, gone = true }
                    PintHUD.notify('~b~Spectating ~w~' .. (GetPlayerName(target) or '?'))
                end
            end
        elseif spectate.reported and not IsEntityDead(PlayerPedId()) then
            spectate = { on = false, reported = false, targetId = nil, gone = false }
        end
    end
end)

-- The revive circle. Stand in it and HOLD - a countdown runs on the spot so
-- the reviver knows exactly how long to keep their nerve with a horde closing
-- in, and stepping out resets it. The downed player is told when help arrives.
CreateThread(function()
    local hold     = { id = nil, since = 0 }
    local lastPing = 0

    while true do
        if state.active and #downed.list > 0 then
            Wait(0)

            local me      = GetPlayerServerId(PlayerId())
            local alive   = not IsEntityDead(PlayerPedId())
            local myPos   = GetEntityCoords(PlayerPedId())
            local now     = GetGameTimer()
            local holding = nil

            for _, entry in ipairs(downed.list) do
                local at   = vector3(entry.x, entry.y, entry.z)
                -- On foot only: no leaning out of the van to revive someone.
                local onFoot = GetVehiclePedIsIn(PlayerPedId(), false) == 0
                local near   = alive and onFoot and entry.id ~= me
                    and #(myPos - at) < Config.reviveRadius

                if near then holding = entry.id end

                DrawMarker(1, entry.x, entry.y, entry.z - 0.95,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    Config.reviveRadius * 2.0, Config.reviveRadius * 2.0, 1.3,
                    near and 120 or 210, near and 240 or 90, 120, 110,
                    false, false, 2, false, nil, nil, false)

                local label

                if hold.id == entry.id then
                    -- Reviver's view: their own, most accurate countdown.
                    local left = Config.reviveHoldSeconds - (now - hold.since) / 1000
                    label = ('~g~REVIVING  %.1f'):format(math.max(0.0, left))
                elseif entry.holdLeft then
                    -- Everyone else, including the person on the floor, sees
                    -- the same countdown broadcast by the server.
                    label = ('~g~REVIVING  %.1f'):format(entry.holdLeft)
                elseif entry.id == me then
                    -- Downed player's view: is anyone actually coming?
                    local helper = false
                    for _, playerId in ipairs(GetActivePlayers()) do
                        if playerId ~= PlayerId() then
                            local ped = GetPlayerPed(playerId)
                            if DoesEntityExist(ped) and not IsEntityDead(ped)
                                and #(GetEntityCoords(ped) - at) < Config.reviveRadius then
                                helper = true
                                break
                            end
                        end
                    end

                    label = (entry.held or helper)
                        and ('~g~BEING REVIVED - clock held at %ds'):format(entry.remaining)
                        or  ('~o~YOU ARE DOWN  %ds'):format(entry.remaining)
                else
                    label = ('~o~%s  %ds'):format(entry.name, entry.remaining)
                end

                local onScreen, sx, sy = World3dToScreen2d(entry.x, entry.y, entry.z + 1.0)
                if onScreen then
                    SBM.drawText(label, sx, sy, 0.42)
                end
            end

            -- Hold bookkeeping: stepping out of the circle resets the clock.
            if holding then
                if hold.id ~= holding then
                    hold = { id = holding, since = now }
                elseif (now - hold.since) >= Config.reviveHoldSeconds * 1000 then
                    TriggerServerEvent('pint:tryRevive', holding)
                    hold = { id = nil, since = 0 }
                end

                -- Tell the server their clock is being held.
                if (now - lastPing) > 300 then
                    lastPing = now
                    TriggerServerEvent('pint:attending', holding,
                        math.max(0.0, Config.reviveHoldSeconds - (now - hold.since) / 1000))
                end
            elseif hold.id then
                hold = { id = nil, since = 0 }
            end
        else
            Wait(300)
        end
    end
end)

-- Everyone joins the same gang, nobody is the same bloke. A model swap wipes
-- weapons, so the sidearm is re-issued after.
local function applyGangLook(gangIndex)
    local models = Config.gang.models
    local name   = models[(((gangIndex or 1) - 1) % #models) + 1]

    local hash = SBM.loadModel(name)
    if not hash then return end

    SetPlayerModel(PlayerId(), hash)
    SetModelAsNoLongerNeeded(hash)

    local ped = PlayerPedId()
    SetPedRandomComponentVariation(ped, 0)
    SetPedRandomProps(ped)

    GiveWeaponToPed(ped, GetHashKey(Config.player.weapon), Config.player.ammoStart, false, true)
end

RegisterNetEvent('pint:begin', function(missionName, spawnIndex, gangIndex)
    local mission = Config.missions[missionName]
    if not mission then return end

    local ped = PlayerPedId()

    DoScreenFadeOut(600)
    Wait(700)

    stopSpectate()
    TriggerEvent('infected:clearBodies') -- no leftover corpses at the start line

    -- Scatter missions give each player their own washed-up spot.
    local at = (spawnIndex and mission.scatterSpawns and mission.scatterSpawns[spawnIndex])
        or mission.start.pos

    -- Wipe-restart case: everyone is a corpse. Resurrect first.
    if IsEntityDead(ped) then
        exports.spawnmanager:spawnPlayer({
            x = at.x, y = at.y, z = at.z,
            heading = mission.start.heading or 0.0,
            model = GetEntityModel(ped), skipFade = true,
        })
        Wait(1500)
    end

    applyGangLook(gangIndex)
    ped = PlayerPedId()

    -- Mission deaths are final until the wipe: no auto-respawn.
    exports.spawnmanager:setAutoSpawn(false)

    SetEntityCoords(ped, at.x + math.random(-3, 3), at.y + math.random(-3, 3), at.z, false, false, false, false)
    SetEntityHeading(ped, mission.start.heading or 0.0)

    -- Settle onto the ground once collision streams in - hand-placed z values
    -- must never leave anyone knee-deep in the map.
    Wait(900)
    ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 30.0, false)
    if found then
        SetEntityCoords(ped, pos.x, pos.y, groundZ + 1.0, false, false, false, false)
    end

    TriggerEvent('pint:spawnMyCar', at, gangIndex)

    DoScreenFadeIn(800)

    clearBlip()
    setState({
        active           = true,
        mission          = missionName,
        stageIndex       = 0,
        blip             = nil,
        checkpoint       = at,
        claimedGarrisons = {},
    })
    PintHUD.set({ gather = '__clear', regroup = '__clear', missionName = mission.shard.title })
    PintHUD.shard(mission.shard.title, mission.shard.sub)
end)

RegisterNetEvent('pint:stage', function(missionName, index)
    local mission = Config.missions[missionName]
    local data    = mission and mission.stages[index]
    if not data then return end

    local previous = mission.stages[index - 1]

    setState({
        active     = true,
        mission    = missionName,
        stageIndex = index,
        blip       = setStageBlip(data.target),
        checkpoint = previous and previous.target or mission.start.pos,
        notice     = {
            text      = ('~y~%s~n~~w~%s'):format(data.title, data.flavour),
            showUntil = GetGameTimer() + 14000,
        },
    })

    PintHUD.set({ objective = data.title, holdout = '__clear', gather = '__clear',
                  regroup = '__clear', secure = '__clear', secureWaves = '__clear' })
    PintHUD.notify('~y~' .. data.title .. '~w~ - ' .. data.flavour)

    -- Big banner for every new objective. Skipped on the first stage, where
    -- the mission's own shard has just played and two would stack on top of
    -- each other.
    if Config.stageShard and index > 1 then
        PintHUD.shard(data.title, data.flavour)
    end

    -- The single-player checkpoint chime on every stage transition.
    PlaySoundFrontend(-1, 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', true)
end)

RegisterNetEvent('pint:holdout', function(remaining)
    PintHUD.set({ holdout = remaining })
end)

RegisterNetEvent('pint:secure', function(remaining, holding, cleared, need)
    -- Waves still outstanding render as a counter; once they are all down
    -- the line falls back to the plain floor countdown.
    local waves = (need and (cleared or 0) < need)
        and ('%d/%d'):format(cleared or 0, need) or '__clear'

    -- nil from the server means the gate is over. Without the explicit
    -- clear the merge would skip the key and the SECURE line would squat
    -- on the HUD into the next stage.
    PintHUD.set({
        secure      = remaining ~= nil and remaining or '__clear',
        secureHeld  = holding and true or false,
        secureWaves = waves,
    })
end)

RegisterNetEvent('pint:gather', function(delivered, required)
    PintHUD.set({ gather = ('%d/%d'):format(delivered, required) })
end)

RegisterNetEvent('pint:regroup', function(present, total)
    PintHUD.set({ regroup = ('%d/%d'):format(present, total) })
end)

RegisterNetEvent('pint:ammo', function(rounds)
    local amount = rounds or Config.player.ammoReward
    AddAmmoToPed(PlayerPedId(), GetHashKey(Config.player.weapon), amount)
    PintHUD.notify(('~g~+%d rounds.'):format(amount))
end)

RegisterNetEvent('pint:armour', function()
    SetPedArmour(PlayerPedId(), 100)
    PintHUD.notify('~g~Stab vest.~w~ Fashionable AND practical.')
end)

-- The chosen client spawns the garrison locally: those peds are then owned by
-- the player nearest the chokepoint, which is who they will fight first.
RegisterNetEvent('pint:spawnGarrison', function(index)
    local mission  = M()
    local garrison = mission and mission.garrisons and mission.garrisons[index]
    if garrison then
        TriggerEvent('infected:garrison', garrison.at, garrison.count)
    end
end)

local function endMission(winShard)
    clearBlip()
    stopSpectate()

    local mission = M()

    setState({ active = false, stageIndex = 0, blip = nil })
    PintHUD.set({ objective = '__clear', holdout = '__clear', distance = '__clear',
                  gather = '__clear', regroup = '__clear', missionName = '__clear',
                  secure = '__clear', secureWaves = '__clear' })

    -- Back to sandbox rules: auto-respawn on, and anyone still dead gets up.
    exports.spawnmanager:setAutoSpawn(true)
    if IsEntityDead(PlayerPedId()) then
        exports.spawnmanager:spawnPlayer()
    end

    if winShard and mission then
        -- The real deal: MISSION PASSED fanfare.
        PlaySoundFrontend(-1, 'MISSION_PASS_NOTIFY', 'HUD_AWARDS', true)
        PintHUD.shard(mission.win.title, mission.win.subtitle)
    end
end

RegisterNetEvent('pint:win', function(boat)
    -- The boat. It was always meant to arrive; now it does.
    if boat then
        CreateThread(function()
            local hash = SBM.loadModel(boat.model, 6000)
            if not hash then return end

            local vessel = CreateVehicle(hash, boat.pos.x, boat.pos.y, boat.pos.z, boat.pos.w, true, true)
            SetModelAsNoLongerNeeded(hash)

            if DoesEntityExist(vessel) then
                SetEntityAsMissionEntity(vessel, true, true)
                local blip = AddBlipForEntity(vessel)
                SetBlipSprite(blip, 427)
                SetBlipColour(blip, 2)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString('The boat')
                EndTextCommandSetBlipName(blip)
            end
        end)
    end

    endMission(true)
end)
RegisterNetEvent('pint:ended', function() endMission(false) end)

-- Total party kill. Hold on the corpse cam; the server restarts the mission
-- in a few seconds and pint:begin resurrects everyone at the start.
RegisterNetEvent('pint:wipe', function()
    clearBlip()
    setState({ active = false, stageIndex = 0, blip = nil })
    PintHUD.set({ objective = '__clear', holdout = '__clear', distance = '__clear',
                  gather = '__clear', regroup = '__clear', missionName = '__clear',
                  secure = '__clear', secureWaves = '__clear' })
    PlaySoundFrontend(-1, 'ScreenFlash', 'WastedSounds', true)
    PintHUD.shard('YOU ALL DIED', 'From the top. Gaz is sorry.')
end)

-- Zone watcher. goto stages report arrival; regroup stages ping presence so
-- the server can see when everyone is in at once. Distance is 2D on purpose -
-- a couple of metres of z error must never block a checkpoint.
-- Living infected near the player. They carry a decor rather than a
-- relationship group, because groups are set by whoever spawned the ped and
-- every other machine sees a default - the decor is the only thing that syncs.
local function infectedWithin(radius)
    local me    = GetEntityCoords(PlayerPedId())
    local count = 0

    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsEntityDead(ped) and not IsPedAPlayer(ped)
            and DecorExistOn(ped, 'SBM_INF') and DecorGetBool(ped, 'SBM_INF')
            and #(GetEntityCoords(ped) - me) < radius then
            count = count + 1
        end
    end

    return count
end

CreateThread(function()
    while true do
        Wait(500)

        local stage = currentStage()

        if stage and (stage.type == 'goto' or stage.type == 'regroup' or stage.type == 'gather') then
            local me   = GetEntityCoords(PlayerPedId())
            local dist = #(vector2(me.x, me.y) - vector2(stage.target.x, stage.target.y))

            PintHUD.set({ distance = formatDistance(dist) })

            if stage.type == 'goto' then
                local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
                local seated  = (not stage.requireVehicle) or vehicle ~= 0

                -- Some objectives want the area earned, not just reached.
                if stage.requireClear then
                    local left = infectedWithin(stage.requireClear)
                    if left > 0 then
                        seated = false
                        PintHUD.set({ distance = ('%d still up'):format(left) })
                    end
                end

                -- A refuelling objective is done when the tank is done.
                if stage.requireFuel then
                    local fuel = (vehicle ~= 0 and DecorExistOn(vehicle, 'SBM_FUEL'))
                        and DecorGetFloat(vehicle, 'SBM_FUEL') or 0.0
                    seated = seated and vehicle ~= 0 and fuel >= stage.requireFuel
                end

                if seated and dist < stage.radius
                    and (GetGameTimer() - state.lastZonePing) > 3000 then
                    setState({ lastZonePing = GetGameTimer() })
                    TriggerServerEvent('pint:zoneReached', state.stageIndex)
                end
            elseif stage.type == 'regroup' then
                setState({ zoneTicks = state.zoneTicks + 1 })
                if state.zoneTicks % 4 == 0 then
                    TriggerServerEvent('pint:inZone', dist < stage.radius)
                end
            end
        else
            PintHUD.set({ distance = '__clear' })
        end
    end
end)

-- Garrison lookout: first player near a chokepoint claims its infestation.
CreateThread(function()
    while true do
        Wait(2000)

        local mission = M()

        if state.active and mission and mission.garrisons then
            local me = GetEntityCoords(PlayerPedId())

            for index, garrison in ipairs(mission.garrisons) do
                if not state.claimedGarrisons[index]
                    and #(vector2(me.x, me.y) - vector2(garrison.at.x, garrison.at.y)) < garrison.trigger then
                    local claimed = {}
                    for key, value in pairs(state.claimedGarrisons) do claimed[key] = value end
                    claimed[index] = true
                    setState({ claimedGarrisons = claimed })

                    TriggerServerEvent('pint:claimGarrison', index)
                end
            end
        end
    end
end)

-- Presence report: objective timers must not run down while everyone is
-- sitting in a vehicle, or while nobody is in the circle at all.
CreateThread(function()
    while true do
        Wait(1000)

        local stage = currentStage()

        if stage then
            local ped  = PlayerPedId()
            local me   = GetEntityCoords(ped)
            local dist = #(vector2(me.x, me.y) - vector2(stage.target.x, stage.target.y))

            TriggerServerEvent('pint:presence',
                dist < stage.radius,
                GetVehiclePedIsIn(ped, false) ~= 0,
                not IsEntityDead(ped))
        end
    end
end)

-- Proximity report for gradient-difficulty missions.
CreateThread(function()
    while true do
        Wait(8000)

        local mission = M()

        if state.active and mission and mission.cityIntensity then
            local me     = GetEntityCoords(PlayerPedId())
            local centre = mission.cityIntensity.centre
            TriggerServerEvent('pint:pos',
                #(vector2(me.x, me.y) - vector2(centre.x, centre.y)))
        end
    end
end)

-- Layman's signage: a bobbing arrow over the objective, a ground ring showing
-- the arrival zone, and a help box that stays up long enough to actually read.
local function showHelp(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

CreateThread(function()
    while true do
        Wait(0)

        local stage = currentStage()

        if stage then
            if state.notice and GetGameTimer() < state.notice.showUntil then
                showHelp(state.notice.text)
            end

            local target = stage.target
            local me     = GetEntityCoords(PlayerPedId())

            if #(vector2(me.x, me.y) - vector2(target.x, target.y)) < 180.0 then
                -- The classic bouncing arrow, over the van / the pump / the pub.
                if stage.type ~= 'holdout' then
                    DrawMarker(0, target.x, target.y, target.z + 2.4,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        0.9, 0.9, 0.9, 245, 200, 66, 210,
                        true, false, 2, true, nil, nil, false)
                end

                -- The zone itself, drawn on the ground - includes holdouts, so
                -- "stay in this spot" is literally a visible circle.
                DrawMarker(1, target.x, target.y, target.z - 1.5,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    stage.radius * 2.0, stage.radius * 2.0, 2.5,
                    245, 200, 66, 60,
                    false, false, 2, false, nil, nil, false)
            end
        else
            Wait(400)
        end
    end
end)

-- Respawn at the last checkpoint while the mission runs; default spawns
-- otherwise.
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    exports.spawnmanager:setAutoSpawnCallback(function()
        if state.active and state.checkpoint then
            local at = state.checkpoint

            exports.spawnmanager:spawnPlayer({
                x       = at.x + math.random(-3, 3),
                y       = at.y + math.random(-3, 3),
                z       = at.z,
                heading = 0.0,
                model   = GetEntityModel(PlayerPedId()),
            })
        else
            exports.spawnmanager:spawnPlayer()
        end
    end)

    exports.spawnmanager:setAutoSpawn(true)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    clearBlip()
end)

-- No friendly fire on a mission. Survivors are on the same side by
-- definition, and friendly fire switched on by another game mode must never
-- follow anyone in here.
CreateThread(function()
    while true do
        Wait(2000)

        if state.active then
            NetworkSetFriendlyFireOption(false)
            SetCanAttackFriendly(PlayerPedId(), false, false)
        end
    end
end)
