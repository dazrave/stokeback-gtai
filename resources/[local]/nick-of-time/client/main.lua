-- Round lifecycle, roles, spawns and the shared HUD. The police brain and the
-- robber brain live in their own files and read state through NickState().
--
-- The spawning here is chase's, near enough word for word: it is the code that
-- stopped cars landing on their roofs and players landing in the sky, and both
-- of those cost an evening each.
local state = {
    role   = nil,
    status = {},
    purse  = {},  -- his numbers; only ever sent to him
    police = {},  -- their numbers; only ever sent to them
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

-- The police-only half of the status. Kept out of the shared broadcast on
-- purpose: "your helicopter is available" is the same sentence as "they have
-- completely lost you", and he is never told that in words.
function NickPolice()
    return state.police
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

-- A paired animation, guarded. Both halves of the pull-out ask for this, and
-- neither may ever depend on it: if the dictionary will not stream (a bad
-- name, a slow disk, a stripped install) the interaction still has to happen,
-- so this returns quietly and the ragdoll does the acting instead.
function NickAnim(dict, clip, ms)
    if not dict or not clip then return end

    RequestAnimDict(dict)

    local deadline = GetGameTimer() + 1200
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > deadline then return end
        Wait(25)
    end

    TaskPlayAnim(PlayerPedId(), dict, clip, 8.0, -8.0, ms or 1000, 0, 0.0, false, false, false)
    RemoveAnimDict(dict)
end

local loadModel = SBM.loadModel
local roundCars = SBM.tracker()

-- Every script car goes to the server by network id, the way the patrols do.
-- The local tracker is still the first sweep; the server's copy exists for
-- the one case a tracker cannot cover - this client disconnecting mid-round,
-- after which its cars migrate to whoever was stood nearby and would outlive
-- the round (acceptance test 8 counts cars too). police.lua uses it for the
-- relief cruisers.
function NickReportCar(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId == 0 then return end

    SetNetworkIdCanMigrate(netId, true)
    TriggerServerEvent('nick:carUp', netId)
end

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

    NickReportCar(vehicle)

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

    setState({ role = role.isRobber and 'robber' or 'police', purse = {}, police = {} })

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

RegisterNetEvent('nick:police', function(police)
    setState({ police = police or {} })
end)

RegisterNetEvent('nick:purseNote', function(message)
    NickHUD.notify('~y~' .. tostring(message))
end)

RegisterNetEvent('nick:banked', function(value)
    NickHUD.shard('STASHED', NickHUD.money(value) .. ' safely out of your hands.')
end)

-- The whistle went and they could see him. Both sides get the card, because
-- the whole drama of the next three minutes is that everyone knows the terms.
RegisterNetEvent('nick:sudden', function(seconds)
    if not state.role then return end

    local minutes = math.floor((seconds or 180) / 60)

    NickHUD.shard('SUDDEN DEATH', state.role == 'robber'
        and ('They saw you on the whistle. %d minutes out of sight and it is all yours.'):format(minutes)
        or  ('He was in view when time went. Keep eyes on him for %d minutes and he loses the lot.'):format(minutes))
end)

-- The last thirty seconds, out loud. A man hiding in an alley listening to a
-- countdown is the best thing this mode does.
RegisterNetEvent('nick:suddenTick', function(left)
    if not state.role or not left then return end

    if left <= 5 or left % 10 == 0 then
        NickHUD.notify(('~r~%d'):format(left))
    end
end)

RegisterNetEvent('nick:end', function(result, robberName, stashed)
    -- A fresh table, NOT setState: `role = nil` in a constructor handed to a
    -- merge is simply absent, so the old role survived the round - and the
    -- three maintenance loops below, all gated on state.role, kept running
    -- drive-by, damage and wanted-level overrides into free roam forever.
    state = { role = nil, status = {}, purse = {}, police = {}, map = { sites = {}, houses = {} } }

    local shards = {
        arrested = { 'NICKED', ('Bag confiscated. %s kept %s.'):format(robberName or '?', NickHUD.money(stashed)) },
        ['got-away']   = { 'AWAY CLEAN', ('Nobody had eyes on him at the whistle. %s kept the lot - %s.'):format(robberName or '?', NickHUD.money(stashed)) },
        ['went-quiet'] = { 'GONE TO GROUND', ('Three minutes of absolutely nothing. %s finished on %s.'):format(robberName or '?', NickHUD.money(stashed)) },
        ['run-down']   = { 'WORN DOWN', ('%s never got three quiet minutes. Finished on %s.'):format(robberName or '?', NickHUD.money(stashed)) },
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
                SetVehicleEngineCanDegrade(vehicle, true)
                SetVehicleCanBreak(vehicle, true)

                -- The one exception, and it is the robber's tank. GTA lights a
                -- badly damaged petrol tank on its OWN schedule, which would
                -- end rounds with a fireball nobody caused and no story to
                -- tell. Clamped, so the only thing that ever sets the getaway
                -- car alight is the damage ladder in robber.lua (plan §11).
                if state.role == 'robber' then
                    SetDisableVehiclePetrolTankDamage(vehicle, true)
                    SetVehiclePetrolTankHealth(vehicle, Config.damage.PETROL_TANK_CLAMP)
                else
                    SetDisableVehiclePetrolTankDamage(vehicle, false)
                end
            end
        end
    end
end)

-- GTA's own wanted system stays off and its stars stay on: the real one would
-- spawn its own police (who would arrest, shoot and end rounds - all three
-- forbidden by pillar 3), so the level is pinned at zero and the STARS are
-- painted on top of it by hand off what he has actually stashed. He gets the
-- glorious feeling of being at four stars with none of the stock dispatch
-- behind it; the only law tonight is human plus our own patrols.
CreateThread(function()
    while true do
        Wait(1000)

        if state.role then
            SetMaxWantedLevel(0)
            SetPlayerWantedLevel(PlayerId(), 0, false)
            SetPlayerWantedLevelNow(PlayerId(), false)

            -- Nothing stock ever spawns (plan §5.4). Both of these have to be
            -- re-asserted rather than set once: the engine turns them back on
            -- across streaming and respawns.
            SetCreateRandomCops(false)
            SetCreateRandomCopsNotOnScenarios(false)
            SetCreateRandomCopsOnScenarios(false)

            for service = 1, 15 do
                EnableDispatchService(service, false)
            end

            -- The fake stars are his and his alone: the police read his heat
            -- off the HUD line, and a star on a copper's screen would just be
            -- confusing.
            if state.role == 'robber' then
                SetFakeWantedLevel(state.status.stars or 0)
            end
        end
    end
end)

-- ===== the HUD =====
-- One line, top centre. The clock, then whichever truth belongs to your side:
-- the police see what has been REPORTED taken, he sees what is actually in the
-- bag. That gap is the mode.
-- The map treats every source of a hard lock identically (pillar 1). The HUD
-- does not: a copper who is LOOKING at him and a patrol car radioing him in
-- should never feel like the same thing, even when the dot is the same dot.
local CONTACT_LINES = {
    hard   = '~r~EYES ON',
    patrol = '~o~PATROL HAS HIM',
    air    = '~r~AIR SUPPORT - HE IS LIT UP',
    soft   = '~y~SEARCHING',
    cold   = '~c~NO CONTACT',
}

CreateThread(function()
    while true do
        Wait(0)

        local status = state.status

        if state.role and status.phase and status.phase ~= 'idle' then
            local remaining = status.remaining or 0
            local clock     = ('%d:%02d'):format(math.floor(remaining / 60), remaining % 60)

            -- SUDDEN DEATH replaces the round clock with the one number that
            -- matters: how much unbroken quiet he has left to serve. Same
            -- figure on both sides, opposite feelings, which is the mode in
            -- one line. It goes red and stays red - nobody should have to
            -- work out which clock they are looking at.
            if status.sudden then
                local quiet = status.quietLeft or 0
                clock = ('~r~SUDDEN DEATH ~w~%d:%02d'):format(
                    math.floor(quiet / 60), quiet % 60)
            end
            local stars     = (status.stars or 0) > 0 and (' ~r~' .. string.rep('*', status.stars)) or ''

            local line

            local second = nil

            if state.role == 'police' then
                local key = status.contact == 'hard' and (status.via == 'eyes' and 'hard' or status.via)
                    or status.contact
                local contact = CONTACT_LINES[key or 'cold'] or CONTACT_LINES.cold

                if status.contact == 'soft' and status.unseenFor then
                    contact = ('~y~SEARCHING - %ds since anyone saw him'):format(status.unseenFor)
                end

                line = ('%s   ~w~reported taken %s%s'):format(
                    contact, NickHUD.money(status.publicTaken or 0), stars)

                -- The favour, when it is theirs to call. Only ever on their
                -- screens: see NickPolice().
                if state.police.heliReady then
                    second = '~b~AIR SUPPORT AVAILABLE~w~ - press '
                        .. (Config.controls.SECONDARY_LABEL or 'G')
                end
            else
                local purse = state.purse

                -- ON YOU and STASHED, the two numbers the whole mode is about.
                -- ON YOU includes whatever the car under him is worth at its
                -- current health, so being rammed visibly costs him money.
                line = ('~y~ON YOU %s   ~g~STASHED %s%s'):format(
                    NickHUD.money(purse.onYou or purse.carried or 0),
                    NickHUD.money(purse.stashed or 0), stars)

                -- How she is doing, while he is in her. The ladder runs on
                -- engine health, so that is the number that gets shown -
                -- night one taught us damage nobody can SEE reads as damage
                -- that is not happening ("there's no car health?").
                local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
                if vehicle ~= 0 then
                    local engine = math.max(0, math.floor(GetVehicleEngineHealth(vehicle) / 10))
                    line = line .. ('   %sHER %d%%'):format(engine <= 25 and '~r~' or '~w~', engine)
                end

                -- What the next safehouse run is actually worth. His alone -
                -- on a police HUD this number would be a live position update
                -- in disguise, which acceptance test 9 exists to forbid.
                local onYou = purse.onYou or purse.carried or 0
                if onYou > 0 then
                    second = ('~g~IF YOU BANK +%s'):format(NickHUD.money(onYou))
                end

                -- In sudden death the bag is already promised to him if he
                -- can just be nobody for three minutes, so the line changes
                -- to say the thing he is actually playing for.
                if status.sudden then
                    second = ('~r~STAY OUT OF SIGHT~w~ - %s rides on it')
                        :format(NickHUD.money(onYou))
                end
            end

            local delta = ''
            if status.leader and status.delta then
                delta = status.delta > 0
                    and ('   ~w~%s ahead by %s'):format(status.leader.name, NickHUD.money(status.delta))
                    or  ('   ~g~leading by %s'):format(NickHUD.money(-status.delta))
            end

            NickHUD.draw(clock .. '   ' .. line .. delta, Config.hud.x, Config.hud.y)

            if second then
                NickHUD.draw(second, Config.hud.x, Config.hud.y + 0.032, Config.hud.scale * 0.8)
            end
        else
            Wait(400)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    roundCars.sweep()
end)
