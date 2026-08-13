-- The robber's brain: the bag, the two ways into a shop, the dive, and the
-- getaway car's slow public death.
--
-- Everything expensive runs on HIS machine on purpose - it owns his ped, so
-- nothing anybody else does can put him under the health floor, and the police
-- never receive a single number that could be read as his position.
local memo = {
    lastVehicle = 0,
    bodyHealth  = nil,
    hits        = 0,
    onFire      = false,
    nextStutter = 0,
    hidden      = false,
    inHouse     = 0,   -- game time we entered a safehouse zone
    pressure    = 0,
    pressureAt  = 0,
    blips       = {},
}

local function isRobber()
    local role, status = NickState()
    return role == 'robber' and status.phase == 'active'
end

local function nearest(list, radius)
    if not list then return nil end

    local me = GetEntityCoords(PlayerPedId())
    local bestIndex, bestGap = nil, nil

    for index, place in ipairs(list) do
        local gap = #(vector3(place.x, place.y, place.z) - me)
        if gap <= radius and (not bestGap or gap < bestGap) then
            bestIndex, bestGap = index, gap
        end
    end

    return bestIndex
end

local function help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

-- ===== his map =====
-- He sees the shops AND this round's safehouses; the police only ever get the
-- shops. Drawn here rather than in main.lua so the two roles can never
-- accidentally share a blip list.
local function clearBlips()
    for _, blip in ipairs(memo.blips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    memo.blips = {}
end

CreateThread(function()
    while true do
        Wait(1000)

        local role, status = NickState()

        if role == 'robber' and status.phase and status.phase ~= 'idle' then
            if #memo.blips == 0 then
                local map = NickMap()

                for _, site in ipairs(map.sites or {}) do
                    local blip = AddBlipForCoord(site.x, site.y, site.z)
                    SetBlipSprite(blip, 1)
                    SetBlipColour(blip, 5)
                    SetBlipScale(blip, 0.7)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentString(site.name or 'Shop')
                    EndTextCommandSetBlipName(blip)
                    memo.blips[#memo.blips + 1] = blip
                end

                for _, house in ipairs(map.houses or {}) do
                    local blip = AddBlipForCoord(house.x, house.y, house.z)
                    SetBlipSprite(blip, 1)
                    SetBlipColour(blip, 2) -- green: the only number that scores
                    SetBlipScale(blip, 0.8)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentString(house.name or 'Safehouse')
                    EndTextCommandSetBlipName(blip)
                    memo.blips[#memo.blips + 1] = blip
                end
            end
        elseif #memo.blips > 0 then
            clearBlips()
        end
    end
end)

-- ===== the heartbeat =====
-- Once a second, to the server and no further. It is what the drain, the stash
-- and the dive are measured against; the police only ever get his position by
-- pointing their eyes at him.
CreateThread(function()
    while true do
        Wait(1000)

        local role, status = NickState()
        if role == 'robber' and status.phase and status.phase ~= 'idle' then
            TriggerServerEvent('nick:heartbeat', GetEntityCoords(PlayerPedId()))
        end
    end
end)

-- ===== the two ways in, and the way out =====
CreateThread(function()
    while true do
        Wait(0)

        if not isRobber() then
            Wait(300)
        else
            local map   = NickMap()
            local purse = NickPurse()
            local ped   = PlayerPedId()
            local onFoot = not IsPedInAnyVehicle(ped, false)

            local site  = onFoot and nearest(map.sites, Config.looting.ZONE_RADIUS) or nil
            local house = onFoot and nearest(map.houses, Config.safehouses.ZONE_RADIUS) or nil

            if purse.job then
                -- Already at it. The only decision left is when to leave, and
                -- the alarm state is the only hint he gets about that.
                help(purse.job.alarmed
                    and '~r~ALARM GOING~w~ - walk out of the zone whenever you like'
                    or  'Filling the bag. Walk out of the zone to stop.')

            elseif site then
                help('~INPUT_PICKUP~ Quiet entry ~w~(full till, alarm on a timer you cannot see)  ~n~'
                    .. '~INPUT_DETONATE~ Smash and grab ~w~(faster, smaller, alarm now)')

                if IsControlJustReleased(0, Config.controls.PRIMARY) then
                    TriggerServerEvent('nick:job', site, 'quiet')
                elseif IsControlJustReleased(0, Config.controls.SECONDARY) then
                    TriggerServerEvent('nick:job', site, 'smash')
                end

            elseif house then
                local carried = purse.carried or 0

                help(('~INPUT_PICKUP~ Stash %s  ~n~~INPUT_DETONATE~ Call it a day ~w~(ends the round, keeps %s)')
                    :format(NickHUD.money(carried), NickHUD.money(purse.stashed or 0)))

                if IsControlJustReleased(0, Config.controls.PRIMARY) then
                    TriggerServerEvent('nick:stash', house)
                elseif IsControlJustReleased(0, Config.controls.SECONDARY) then
                    TriggerServerEvent('nick:callItADay')
                end
            end
        end
    end
end)

-- ===== the dive =====
-- Round a corner, through a doorway, gone. A routing bucket is the only thing
-- that makes him genuinely invisible rather than merely hard to see - the
-- entire force can drive through the doorway and never know - and it is
-- granted by the server, so this only ever ASKS.
--
-- The clear window is the whole point: dive in while somebody has eyes on you
-- and nothing happens, because they watched you do it.
CreateThread(function()
    while true do
        Wait(200)

        local role, status = NickState()

        if role ~= 'robber' or status.phase ~= 'active' then
            if memo.hidden then
                memo.hidden = false
                TriggerServerEvent('nick:vanish', false)
            end
            memo.inHouse = 0
        else
            local ped   = PlayerPedId()
            local house = not IsPedInAnyVehicle(ped, false)
                and nearest(NickMap().houses, Config.safehouses.ZONE_RADIUS) or nil

            if house then
                if memo.inHouse == 0 then memo.inHouse = GetGameTimer() end

                local clear = status.contact ~= 'hard'
                if not clear then memo.inHouse = GetGameTimer() end

                if not memo.hidden and clear
                    and GetGameTimer() - memo.inHouse >= Config.safehouses.SAFEHOUSE_ENTRY_CLEAR_MS then
                    memo.hidden = true
                    TriggerServerEvent('nick:vanish', true)
                    NickHUD.notify('~g~You are off the street.~w~ Let them drive past.')
                end
            else
                memo.inHouse = 0

                if memo.hidden then
                    memo.hidden = false
                    TriggerServerEvent('nick:vanish', false)
                    NickHUD.notify('~y~Back out on the pavement.')
                end
            end
        end
    end
end)

-- ===== pressure =====
-- He never sees the police on his map. He gets a feeling, and a late one:
-- three states, delayed by PRESSURE_UPDATE_DELAY_MS, so he is always reacting
-- to something that was true a moment ago.
local PRESSURE_LINES = { '~g~QUIET', '~y~SOMEONE IS CLOSE', '~r~THEY ARE ON TOP OF YOU' }

CreateThread(function()
    while true do
        Wait(500)

        local role, status = NickState()

        if role == 'robber' and status.phase == 'active' then
            if GetGameTimer() >= memo.pressureAt then
                memo.pressureAt = GetGameTimer() + Config.pressure.PRESSURE_UPDATE_DELAY_MS

                local me    = GetEntityCoords(PlayerPedId())
                local close = 0

                for _, id in ipairs(GetActivePlayers()) do
                    if id ~= PlayerId() then
                        local ped = GetPlayerPed(id)
                        if DoesEntityExist(ped)
                            and #(GetEntityCoords(ped) - me) < Config.pressure.PRESSURE_RADIUS then
                            close = close + 1
                        end
                    end
                end

                memo.pressure = math.min(Config.pressure.PRESSURE_STATES - 1, close)
            end
        else
            memo.pressure = 0
        end
    end
end)

CreateThread(function()
    while true do
        Wait(0)

        local role, status = NickState()

        if role == 'robber' and status.phase == 'active' then
            NickHUD.draw(PRESSURE_LINES[memo.pressure + 1] or PRESSURE_LINES[1],
                Config.hud.x, Config.hud.y + 0.04, Config.hud.scale * 0.85)
        else
            Wait(400)
        end
    end
end)

-- ===== the getaway car's slow public death =====
-- She coughs, she catches, and then she puts him across a pavement in front of
-- three squad cars. Damage is counted the way chase counts it: only another
-- VEHICLE can set the damaged-by-a-vehicle bit (walls and kerbs are map
-- collision, a lamppost is an object), and the threshold throws away the
-- traffic scrapes so only deliberate shunts count.
CreateThread(function()
    while true do
        Wait(500)

        if not isRobber() then
            memo.lastVehicle, memo.hits, memo.onFire = 0, 0, false
        else
            local ped     = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                if vehicle ~= memo.lastVehicle then
                    -- A fresh car is a fresh set of chances.
                    memo.lastVehicle = vehicle
                    memo.bodyHealth  = GetVehicleBodyHealth(vehicle)
                    memo.hits        = 0
                    memo.onFire      = false
                    ClearEntityLastDamageEntity(vehicle)
                end

                local body   = GetVehicleBodyHealth(vehicle)
                local drop   = memo.bodyHealth and (memo.bodyHealth - body) or 0.0
                local engine = GetVehicleEngineHealth(vehicle) / 1000.0

                if HasEntityBeenDamagedByAnyVehicle(vehicle)
                    and drop >= Config.damage.MIN_RAM_DAMAGE then
                    memo.hits = memo.hits + 1
                    ClearEntityLastDamageEntity(vehicle)
                end

                memo.bodyHealth = body

                -- On her last legs: the engine cuts out in little bursts, so
                -- every junction becomes a question.
                if engine <= Config.damage.DAMAGE_STUTTER_THRESHOLD and not memo.onFire
                    and GetGameTimer() >= memo.nextStutter then
                    memo.nextStutter = GetGameTimer() + Config.damage.STUTTER_EVERY_MS

                    local band = Config.damage.DAMAGE_STUTTER_MS
                    SetVehicleEngineOn(vehicle, false, true, true)
                    NickHUD.notify('~y~She is coughing.')
                    Wait(math.random(band[1], band[2]))
                    SetVehicleEngineOn(vehicle, true, true, false)
                end

                -- Enough punishment while she is already dying and she goes up.
                if not memo.onFire
                    and engine <= Config.damage.DAMAGE_STUTTER_THRESHOLD
                    and memo.hits >= Config.damage.DAMAGE_HITS_TO_FIRE then
                    memo.onFire = true

                    NickHUD.shard('SHE\'S GOING UP', 'Out. Now. Run.')
                    StartEntityFire(vehicle)
                    TaskLeaveVehicle(ped, vehicle, 4160) -- bail at speed: that is the joke

                    local doomed = vehicle
                    CreateThread(function()
                        Wait(Config.damage.FIRE_TO_EXPLOSION_MS)
                        if DoesEntityExist(doomed) then
                            NetworkExplodeVehicle(doomed, true, false, false)
                        end
                    end)
                end
            end
        end
    end
end)

-- ===== no guns, endless legs =====
CreateThread(function()
    while true do
        Wait(2000)

        local role, status = NickState()

        if role == 'robber' and status.phase and status.phase ~= 'idle' then
            RemoveAllPedWeapons(PlayerPedId(), true)

            -- The foot chase should end in a tackle, not in him wheezing to a
            -- halt at the end of an alley.
            if Config.pressure.ROBBER_INFINITE_STAMINA then
                RestorePlayerStamina(PlayerId(), 1.0)
            end
        end
    end
end)

-- ===== non-lethal by law =====
-- Straight out of chase, and for the same reason: the round has exactly three
-- endings and none of them is "shot dead in a car park". He takes the hit, he
-- limps, he goes down long enough to be cuffed - he never dies.
CreateThread(function()
    local wasHit, nextKnockdown = false, 0

    while true do
        Wait(0)

        local role, status = NickState()

        if role == 'robber' and status.phase and status.phase ~= 'idle'
            and Config.nonLethal.enabled then
            local ped    = PlayerPedId()
            local health = GetEntityHealth(ped)

            if not IsEntityDead(ped) and health < Config.nonLethal.floorHealth then
                SetEntityHealth(ped, Config.nonLethal.floorHealth)

                if not wasHit then
                    wasHit = true
                    NickHUD.notify('~r~You\'re hit.~w~ Still standing. Move.')
                    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.4)
                end

                local knock = Config.nonLethal.knockdown
                if knock.enabled and not IsPedInAnyVehicle(ped, false)
                    and GetGameTimer() >= nextKnockdown then
                    nextKnockdown = GetGameTimer() + knock.everyMs
                    SetPedToRagdoll(ped, knock.downMs, knock.downMs, 0, true, true, false)
                    NickHUD.notify('~r~DOWN.~w~ Get up before they reach you.')
                end
            elseif health > Config.nonLethal.limpBelow then
                wasHit = false
            end

            SetPedMoveRateOverride(ped, health <= Config.nonLethal.limpBelow and 0.85 or 1.0)
        else
            Wait(500)
        end
    end
end)

RegisterNetEvent('nick:end', function()
    clearBlips()

    if memo.hidden then
        memo.hidden = false
        TriggerServerEvent('nick:vanish', false)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearBlips()
end)
