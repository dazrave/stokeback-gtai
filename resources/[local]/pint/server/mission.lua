-- Campaign director. The server owns the mission pointer and stage pointer;
-- clients own zones, vehicles, wrecks, garrisons and fuel. Horde pressure is
-- delegated entirely to the infected resource's wave director via its exports.
local state = {
    active           = false,
    mission          = nil,
    stageIndex       = 0,
    hordeStarted     = false,
    delivered        = 0,
    regroupIn        = {},
    dead             = {},
    spawnedSpots     = {},
    spawnedWrecks    = {},
    spawnedGarrisons = {},
    spawnedCans      = {},
    spawnedPieces    = {},
    spawnedStashes   = {},
    takenStashes     = {},
    downed           = {}, -- bleeding out: id -> { name, x, y, z, endsAt }
    presence         = {}, -- id -> { inZone, inVehicle, alive }
    playerDistances  = {},
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

-- Defined at the bottom with the rest of the presence plumbing, declared here
-- because the holdout and secure loops above it call it. Without this it
-- resolves as a nil global and the stage tick dies on the spot.
local circleManned

-- Empty streets for the whole campaign, not just while a wave is up. core
-- arbitrates so two modes can't fight over the density natives, and it drops
-- the claim by itself if this resource falls over.
--
-- pcall'd because core may not be up yet, and a campaign that refuses to start
-- because the city is slightly too busy would be a worse bug than the litter.
local function claimStreets()
    local ok, err = pcall(function()
        if state.active then
            exports.core:setPopulation('empty')
        else
            exports.core:clearPopulation()
        end

        -- Tell the horde the apocalypse is on for the whole campaign, not just
        -- while a wave is up. infected has always exported setEngaged for
        -- exactly this and nothing ever called it, so during travel - which is
        -- most of a mission - engagedNow() was false and the wanted level was
        -- left unclamped at 5. Shoot anything and GTA dispatched its own
        -- police, which is why emptying the streets did not stop them turning
        -- up: different mechanism entirely.
        exports.infected:setEngaged(state.active)
    end)

    if not ok then
        print('[pint] could not reach core/infected to set the world state: ' .. tostring(err))
    end
end

-- A claim is only made when a mission STARTS, so anything that restarts core
-- or this resource mid-campaign silently repopulated the city - traffic,
-- pedestrians and the police heat system all came back while the mission
-- carried on. Re-state it whenever either side comes up.
AddEventHandler('onResourceStart', function(resource)
    if resource == 'core' or resource == GetCurrentResourceName() then
        claimStreets()
    end
end)

local function tell(message)
    TriggerClientEvent('chat:addMessage', -1, {
        color = { 245, 200, 66 },
        args  = { 'pint', message },
    })
end

local function currentStage()
    local mission = M()
    return mission and mission.stages[state.stageIndex] or nil
end

local function finish()
    local mission = M()

    setState({ active = false, stageIndex = 0 })
    exports.infected:setRunning(false)
    exports.infected:setIntensity(1.0)
    -- The living survivors get a win on the season scoreboard.
    for _, src in ipairs(GetPlayers()) do
        if not state.dead[tonumber(src)] then TriggerEvent('core:stat', tonumber(src), 'wins', 1) end
    end
    claimStreets()
    TriggerClientEvent('pint:win', -1, mission and mission.winBoat or nil)
    tell('Survived. Type /score to see who carried.')

    -- Roll credits, then the radio crackles: the next episode's hook.
    if mission and mission.outro then
        local nextMission = mission.nextMission

        CreateThread(function()
            Wait(12000)
            for _, line in ipairs(mission.outro) do
                tell(line)
                Wait(5000)
            end

            -- The boat/plane actually goes somewhere: straight into the next
            -- episode, unless someone has started something else meanwhile.
            if nextMission and not state.active then
                tell(('Next: %s. Hold on.'):format(
                    Config.missions[nextMission] and Config.missions[nextMission].label or nextMission))
                Wait(6000)
                if not state.active then start(nextMission) end
            end
        end)
    end
end

local function runHoldout(stage)
    CreateThread(function()
        -- Waves belong to the finale ONLY: the director wakes up here and goes
        -- back to sleep at the end. The journey's danger is garrisons, moments
        -- and whatever chases the car - not a wave treadmill.
        exports.infected:setRunning(true)

        local remainingMs = stage.duration * 1000
        local nextWave    = 0

        while state.active and currentStage() == stage do
            local now = GetGameTimer()

            -- The clock only runs while somebody is actually holding the
            -- position on foot. Sitting in the van is not holding it.
            local manned = circleManned(stage)
            if manned then
                remainingMs = remainingMs - 1000
            end

            local remaining = math.max(0, math.ceil(remainingMs / 1000))
            TriggerClientEvent('pint:holdout', -1, remaining)

            if remaining <= 0 then
                return finish()
            end

            if now >= nextWave then
                exports.infected:forceNextWave()
                nextWave = now + stage.waveEveryMs
            end

            Wait(1000)
        end
    end)
end

-- Every objective is defended: arriving is not completing. A wave lands, and
-- the area has to be held before the stage counts - with the same rule as the
-- holdout, so the clock stops if everybody hides in a car.
local function runSecure(stage, index)
    local seconds = stage.secureSeconds or Config.secureSeconds

    -- Some objectives are their own reward (getting in a car, boarding a
    -- boat): nothing to hold, so don't ask anyone to hold it.
    if seconds <= 0 then
        setState({ securing = false })
        tell(stage.done or (stage.title .. ' - done.'))
        advance(index + 1)
        return
    end

    CreateThread(function()
        local remainingMs = seconds * 1000
        local stalledFor  = 0

        exports.infected:setRunning(true)
        exports.infected:forceNextWave()

        while state.active and state.stageIndex == index and state.securing do
            local manned = circleManned(stage)

            if manned then
                remainingMs = remainingMs - 1000
                stalledFor  = 0
            else
                stalledFor = stalledFor + 1000

                -- Nobody has told them why nothing is happening.
                if stalledFor % 12000 == 0 then
                    tell('Nothing is happening because nobody is holding the spot. Out of the cars.')
                end
            end

            TriggerClientEvent('pint:secure', -1,
                math.max(0, math.ceil(remainingMs / 1000)), not manned)

            if remainingMs <= 0 then
                setState({ securing = false })
                exports.infected:setRunning(false)
                TriggerClientEvent('pint:secure', -1, nil, false)
                TriggerClientEvent('pint:ammo', -1, Config.secureAmmo)
                tell(stage.done or 'Area secure.')
                advance(index + 1)
                return
            end

            Wait(1000)
        end
    end)
end

-- Regroup: done when every connected player is inside the zone at once.
local function runRegroup(stage)
    CreateThread(function()
        while state.active and currentStage() == stage do
            -- Only the living need to arrive; the dead are spectating.
            local present, total = 0, 0

            for _, src in ipairs(GetPlayers()) do
                local id = tonumber(src)
                if not state.dead[id] then
                    total = total + 1
                    if state.regroupIn[id] then
                        present = present + 1
                    end
                end
            end

            TriggerClientEvent('pint:regroup', -1, present, total)

            if total > 0 and present >= total then
                tell(stage.done or 'Everyone made it.')
                return advance(state.stageIndex + 1)
            end

            Wait(1500)
        end
    end)
end

function advance(index)
    local mission = M()
    if not mission then return end

    local stage = mission.stages[index]
    if not stage then return finish() end

    setState({ stageIndex = index, delivered = 0, regroupIn = {}, securing = false })

    TriggerClientEvent('pint:stage', -1, state.mission, index)

    if stage.ambush then
        exports.infected:forceNextWave()
    end

    if stage.reward == 'ammo' then
        TriggerClientEvent('pint:ammo', -1)
    elseif stage.reward == 'armour' then
        TriggerClientEvent('pint:armour', -1)
    end

    if stage.type == 'holdout' then
        runHoldout(stage)
    elseif stage.type == 'regroup' then
        runRegroup(stage)
    end
end

local function start(name)
    if state.active then return tell('Mission already running. /pint stop first.') end

    local mission = Config.missions[name]
    if not mission then
        tell(('No mission called "%s". Try /pint list.'):format(tostring(name)))
        return
    end

    setState({
        active           = true,
        mission          = name,
        stageIndex       = 0,
        hordeStarted     = false,
        delivered        = 0,
        regroupIn        = {},
        dead             = {},
        spawnedSpots     = {},
        spawnedWrecks    = {},
        spawnedGarrisons = {},
        spawnedCans      = {},
        spawnedPieces    = {},
        spawnedStashes   = {},
        takenStashes     = {},
        downed           = {},
        playerDistances  = {},
    })
    exports.infected:resetAll()
    exports.infected:setIntensity(mission.intensityFlat or 1.0)

    claimStreets()

    -- Scatter missions hand each player their own spawn, round-robin; the
    -- gang index deals everyone a different member of the same crew.
    local players = GetPlayers()
    for i, src in ipairs(players) do
        local spawnIndex = mission.scatterSpawns
            and (((i - 1) % #mission.scatterSpawns) + 1)
            or nil
        TriggerClientEvent('pint:begin', tonumber(src), name, spawnIndex, i)
    end

    CreateThread(function()
        for _, line in ipairs(mission.intro) do
            if not state.active then return end
            tell(line)
            Wait(7000) -- slow enough to actually read between gunshots
        end

        if state.active then
            advance(1)
        end
    end)
end

local function stop()
    setState({ active = false, stageIndex = 0 })
    exports.infected:setRunning(false)
    exports.infected:setIntensity(1.0)
    -- Hand the streets back. The campaign holds an empty city while it runs.
    claimStreets()

    TriggerClientEvent('pint:ended', -1)
    tell('Mission abandoned. The pint remains theoretical.')
end

-- Total party kill: hold on the bodies, then run the SAME mission again from
-- the top. (Restarting a different episode instead is a one-word change here.)
local function wipe()
    local name = state.mission

    setState({ active = false, stageIndex = 0 })
    exports.infected:setRunning(false)
    exports.infected:setIntensity(1.0)
    TriggerClientEvent('pint:wipe', -1)
    tell('Everyone died. Obviously.')

    -- Back to square one, not just back to stage one: the restart already
    -- sweeps the campaign's own leftovers, but the crew were still lying
    -- wherever they fell, scattered across the map.
    pcall(function() exports.telemetry:resetWorld() end)

    CreateThread(function()
        Wait(10000)
        if not state.active and name then
            start(name)
        end
    end)
end

-- Death is a countdown, not a full stop: you go DOWN where you fell, and a
-- mate who reaches the spot inside the window hauls you back up. Let the clock
-- run out and that's that.
RegisterNetEvent('pint:died', function(coords)
    local source = source
    if not state.active or state.dead[source] or state.downed[source] then return end

    local downed = {}
    for key, value in pairs(state.downed) do downed[key] = value end
    downed[source] = {
        id     = source,
        name   = GetPlayerName(source) or 'Someone',
        x      = coords and coords.x or 0.0,
        y      = coords and coords.y or 0.0,
        z      = coords and coords.z or 0.0,
        endsAt = GetGameTimer() + Config.reviveSeconds * 1000,
    }
    setState({ downed = downed })

    TriggerEvent('telemetry:mark', ('pint:DOWN %s'):format(downed[source].name))
    tell(('%s is DOWN. %d seconds to reach them.'):format(downed[source].name, Config.reviveSeconds))
end)

-- Only the living pick people up.
RegisterNetEvent('pint:tryRevive', function(targetId)
    local source = source
    targetId = tonumber(targetId)

    if not state.active or not targetId then return end
    if state.dead[source] or state.downed[source] then return end

    local entry = state.downed[targetId]
    if not entry then return end

    local downed = {}
    for key, value in pairs(state.downed) do downed[key] = value end
    downed[targetId] = nil
    setState({ downed = downed })

    TriggerClientEvent('pint:revived', targetId, { x = entry.x, y = entry.y, z = entry.z })
    TriggerEvent('telemetry:mark', ('pint:REVIVED %s'):format(entry.name))
    tell(('%s dragged %s back up.'):format(GetPlayerName(source) or 'Someone', entry.name))
end)

-- Someone is knelt over them: the clock HOLDS. You cannot bleed out while a
-- mate is actively working on you, which stops the cruellest outcome of all -
-- dying at 0.1 seconds with your rescuer stood right there.
-- Who is stood where. Objective clocks read this so they never tick down
-- with the crew sat in a car, or with nobody in the circle at all.
RegisterNetEvent('pint:presence', function(inZone, inVehicle, alive)
    local source   = source
    local presence = {}
    for key, value in pairs(state.presence) do presence[key] = value end

    presence[source] = {
        inZone    = inZone and true or false,
        inVehicle = inVehicle and true or false,
        alive     = alive and true or false,
        at        = GetGameTimer(),
    }
    setState({ presence = presence })
end)

-- True when at least one living player is stood in the circle on foot.
function circleManned(stage)
    local now      = GetGameTimer()
    local inCarOk  = stage and stage.holdInVehicle

    for _, entry in pairs(state.presence) do
        if entry.alive and entry.inZone
            and (inCarOk or not entry.inVehicle)
            and (now - entry.at) < 4000 then
            return true
        end
    end

    return false
end

RegisterNetEvent('pint:attending', function(targetId, holdLeft)
    local source = source
    targetId = tonumber(targetId)

    if not state.active or not targetId then return end
    if state.dead[source] or state.downed[source] then return end

    local entry = state.downed[targetId]
    if not entry then return end

    local downed = {}
    for key, value in pairs(state.downed) do downed[key] = value end
    downed[targetId] = {
        id = entry.id, name = entry.name,
        x = entry.x, y = entry.y, z = entry.z,
        endsAt = entry.endsAt, attendedAt = GetGameTimer(),
        holdLeft = tonumber(holdLeft),
    }
    setState({ downed = downed })
end)

-- The bleed-out clock. Broadcasts who is down and how long they have left;
-- expiry is what finally kills someone, and the last expiry is the wipe.
CreateThread(function()
    while true do
        Wait(500)

        if state.active then
            local now       = GetGameTimer()
            local list      = {}
            local refreshed = {}
            local expired   = {}

            for id, entry in pairs(state.downed) do
                -- Attended within the last tick or so? Push the deadline out by
                -- exactly one tick, which freezes the countdown where it is.
                local attended = (now - (entry.attendedAt or 0)) < 1200
                local endsAt   = attended and (entry.endsAt + 500) or entry.endsAt

                if now >= endsAt then
                    expired[#expired + 1] = { id = id, name = entry.name }
                else
                    refreshed[id] = {
                        id = entry.id, name = entry.name,
                        x = entry.x, y = entry.y, z = entry.z,
                        endsAt = endsAt, attendedAt = entry.attendedAt,
                    }

                    list[#list + 1] = {
                        id = id, name = entry.name,
                        x = entry.x, y = entry.y, z = entry.z,
                        remaining = math.ceil((endsAt - now) / 1000),
                        held = attended,
                        holdLeft = attended and entry.holdLeft or nil,
                    }
                end
            end

            local dead = nil

            if #expired > 0 then
                dead = {}
                for key, value in pairs(state.dead) do dead[key] = value end

                for _, gone in ipairs(expired) do
                    dead[gone.id] = true
                    TriggerClientEvent('pint:gone', gone.id)
                    tell(('%s didn\'t make it.'):format(gone.name))
                end
            end

            setState({ downed = refreshed, dead = dead or state.dead })

            if dead then
                local anyLeft = false
                for _, src in ipairs(GetPlayers()) do
                    if not state.dead[tonumber(src)] then
                        anyLeft = true
                    end
                end

                if not anyLeft then
                    wipe()
                end
            end

            TriggerClientEvent('pint:downState', -1, list)
        end
    end
end)

RegisterNetEvent('pint:zoneReached', function(index)
    if not state.active or index ~= state.stageIndex then return end

    local stage = currentStage()
    if not stage or stage.type ~= 'goto' or state.securing then return end

    -- Arrived. Now earn it.
    setState({ securing = true })
    tell(('%s - reached. Hold it.'):format(stage.title))
    runSecure(stage, state.stageIndex)
end)

-- Gather: clients report each delivered can.
RegisterNetEvent('pint:delivered', function()
    if not state.active then return end

    local stage = currentStage()
    if not stage or stage.type ~= 'gather' then return end

    setState({ delivered = state.delivered + 1 })
    TriggerClientEvent('pint:gather', -1, state.delivered, stage.require)
    tell(('Fuel loaded: %d/%d.'):format(state.delivered, stage.require))

    if state.delivered >= stage.require then
        tell(stage.done or 'That\'s the lot.')
        advance(state.stageIndex + 1)
    end
end)

-- Regroup presence pings.
RegisterNetEvent('pint:inZone', function(isIn)
    local source = source
    if not state.active then return end

    local inZone = {}
    for key, value in pairs(state.regroupIn) do inZone[key] = value end
    inZone[source] = isIn and true or nil
    setState({ regroupIn = inZone })
end)

-- One-shot spot claims, server-arbitrated so exactly one client spawns each.
local function claimHandler(field, replyEvent)
    return function(index)
        local source = source

        if not state.active or state[field][index] then return end

        local claimed = {}
        for key, value in pairs(state[field]) do claimed[key] = value end
        claimed[index] = true
        setState({ [field] = claimed })

        TriggerClientEvent(replyEvent, source, index)
    end
end

RegisterNetEvent('pint:claimSpot',     claimHandler('spawnedSpots',     'pint:spawnSpot'))
RegisterNetEvent('pint:claimWreck',    claimHandler('spawnedWrecks',    'pint:spawnWreck'))
RegisterNetEvent('pint:claimGarrison', claimHandler('spawnedGarrisons', 'pint:spawnGarrison'))
RegisterNetEvent('pint:claimCan',      claimHandler('spawnedCans',      'pint:spawnCan'))
RegisterNetEvent('pint:claimStash',    claimHandler('spawnedStashes',   'pint:spawnStash'))

-- A stash is emptied exactly once, by whoever got there first.
RegisterNetEvent('pint:takeStash', function(index)
    local source  = source
    local mission = M()
    local stash   = mission and mission.ammoStashes and mission.ammoStashes[index]

    if not state.active or not stash or state.takenStashes[index] then return end

    local taken = {}
    for key, value in pairs(state.takenStashes) do taken[key] = value end
    taken[index] = true
    setState({ takenStashes = taken })

    TriggerClientEvent('pint:ammoLoot', source, stash.rounds or 18)
    TriggerClientEvent('pint:stashGone', -1, index)
    tell(('%s found ammo.'):format(GetPlayerName(source) or 'Someone'))
end)
RegisterNetEvent('pint:claimPiece',    claimHandler('spawnedPieces',    'pint:spawnPiece'))

-- City-proximity difficulty (gradient missions only): clients report their 2D
-- distance to the mission's centre; the average becomes the wave multiplier.
RegisterNetEvent('pint:pos', function(distance)
    local source  = source
    local mission = M()

    if not state.active or type(distance) ~= 'number' then return end
    if not mission or not mission.cityIntensity then return end

    local distances = {}
    for key, value in pairs(state.playerDistances) do distances[key] = value end
    distances[source] = distance
    setState({ playerDistances = distances })

    local tuning = mission.cityIntensity
    local total, count = 0.0, 0
    for _, dist in pairs(state.playerDistances) do
        local factor = tuning.base - dist / tuning.per
        total = total + math.max(tuning.min, math.min(tuning.max, factor))
        count = count + 1
    end

    if count > 0 then
        exports.infected:setIntensity(total / count)
    end
end)

AddEventHandler('playerDropped', function()
    local source = source

    local distances = {}
    for key, value in pairs(state.playerDistances) do distances[key] = value end
    distances[source] = nil

    local inZone = {}
    for key, value in pairs(state.regroupIn) do inZone[key] = value end
    inZone[source] = nil

    local dead = {}
    for key, value in pairs(state.dead) do dead[key] = value end
    dead[source] = nil

    setState({ playerDistances = distances, regroupIn = inZone, dead = dead })

    -- Rage-quitting doesn't cheat the reaper: if everyone still connected is
    -- dead, that's a wipe. If nobody is left at all, just stand down.
    if state.active then
        local remaining, alive = 0, 0
        for _, src in ipairs(GetPlayers()) do
            local id = tonumber(src)
            if id ~= source then
                remaining = remaining + 1
                if not state.dead[id] then
                    alive = alive + 1
                end
            end
        end

        if remaining == 0 then
            stop()
        elseif alive == 0 then
            wipe()
        end
    end
end)

-- Vignette director: every minute or two, someone gets a show. The list is
-- shuffled and fully cycled before anything repeats.
CreateThread(function()
    local queue = {}

    while true do
        Wait(5000)

        local mission = M()
        local from = mission and (mission.momentsFromStage or 2) or 2

        if state.active and state.stageIndex >= from then
            Wait(math.random(Config.moments.gapMs.min, Config.moments.gapMs.max))

            mission = M()
            from = mission and (mission.momentsFromStage or 2) or 2

            if state.active and state.stageIndex >= from then
                if #queue == 0 then
                    for _, name in ipairs(Config.moments.list) do queue[#queue + 1] = name end
                    for i = #queue, 2, -1 do
                        local j = math.random(i)
                        queue[i], queue[j] = queue[j], queue[i]
                    end
                end

                local players = GetPlayers()
                if #players > 0 then
                    local target = players[math.random(#players)]
                    local moment = table.remove(queue)
                    TriggerClientEvent('pint:moment', tonumber(target), moment)
                    TriggerEvent('telemetry:mark', 'moment:' .. moment)
                end
            end
        end
    end
end)

-- Read by the telemetry snapshot so an overheard request can be filed with
-- the mission and stage that were live when it was said.
exports('getState', function()
    local mission = state.mission and Config.missions[state.mission] or nil
    local stage   = mission and mission.stages[state.stageIndex] or nil

    local downed = 0
    for _ in pairs(state.downed or {}) do downed = downed + 1 end

    return {
        active     = state.active and true or false,
        mission    = state.mission,
        stageIndex = state.stageIndex,
        stageId    = stage and stage.id or nil,
        stageTitle = stage and stage.title or nil,
        securing   = state.securing and true or false,
        downed     = downed,
    }
end)

RegisterCommand('pint', function(source, args)
    local action = args[1] or 'start'

    if action == 'start' then
        start(args[2] or Config.defaultMission)
    elseif action == 'stop' then
        stop()
    elseif action == 'list' then
        for name, mission in pairs(Config.missions) do
            tell(('/pint start %s - %s'):format(name, mission.label))
        end
    elseif action == 'skip' and state.active then
        -- Dev helper: jump the story forward one stage.
        tell(('Skipping "%s".'):format(currentStage() and currentStage().title or '?'))
        advance(state.stageIndex + 1)
    end
end, false)
