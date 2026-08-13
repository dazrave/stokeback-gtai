-- core: the gametype framework. A mode declares WHAT its round needs and the
-- framework does the plumbing every mode used to hand-roll: claim the world,
-- set the stage, deal the teams, run the clock, and put every last piece of
-- furniture back when it ends - however it ends, including the mode falling
-- over mid-round.
--
--     exports.core:RegisterGametype('scrapyard', {
--         label        = 'Scrapyard Kings',
--         teams        = 'ffa',        -- or 'coop', or an explicit list:
--                                      --   { {id='crew', label='The Crew', colour=25,
--                                      --      loadout='survivor', assign=false}, ... }
--                                      --   (assign=false: filled by SetTeam only)
--         population   = 'empty',      -- 'sparse' | 'alive' (alive = leave the city be)
--         police       = 'off',        -- 'ambient' | 'custom' (mode brings its own law)
--         friendlyFire = 'auto',       -- cross-team only; or true / false outright
--         respawn      = { kind = 'where-you-fell', delay = 8, loadout = 'crew' },
--         clock        = { hour = 22, minute = 0, weather = 'FOG', freeze = true },
--         roundSeconds = 600,          -- nil = untimed; the framework calls time
--         minPlayers   = 2,
--         hooks        = { OnStart, OnEnd, OnPlayerJoin, OnPlayerLeave, OnTick },
--     })
--
-- The framework owns the chat command (/scrapyard start|stop) - a ported mode
-- must not register its own duplicate. OnTick runs at ~1Hz while the round is
-- live; every hook is pcall'd so a mode's bug ends its round, not core.
-- OnEnd(reason) may return 'hold' to keep the world claim through a planned
-- restart (see chase) - the mode then owns releasing it.

local registry = {}    -- [name] = { name, label, resource, desc, hooks, live }
local commands = {}    -- one RegisterCommand per name, ever; the closure reads the registry
local active   = nil   -- the registration currently running a round
local endsAt   = nil   -- game timer deadline while a timed round runs
local session  = 0     -- bumped on every start/stop so a stale tick thread knows to die

-- The end-of-round card gets this long to play before the default stack
-- restarts underneath it; a round that goes straight back out inside the
-- grace keeps the claim without churning resources up and down.
local RELEASE_GRACE_MS = 8000

-- modes.lua folds these into its stop-list so claimWorld can stop registered
-- modes it has never heard of. A global, not an export: both files live in
-- core, and a resource cannot call its own exports.
function GametypeResources()
    local out = {}
    for _, g in pairs(registry) do out[#out + 1] = g.resource end
    return out
end

-- Reply to a command, whether it came from a player or the server console.
local function reply(source, msg)
    if source and source > 0 then
        TriggerClientEvent('chat:addMessage', source, { color = { 245, 200, 66 }, args = { 'core', msg } })
    else
        print('[core] ' .. msg)
    end
end

local function runHook(g, name, ...)
    local hook = g.hooks[name]
    if not hook then return nil end

    local ok, result = pcall(hook, ...)
    if not ok then
        print(('[core] gametype %s %s failed: %s'):format(g.name, name, tostring(result)))
        return nil
    end
    return result
end

-- Everything a client needs to be IN the round. Shared by round start (sent
-- to everyone) and by late joiners, who used to miss the start-of-round
-- broadcasts entirely - a player connecting mid-chase kept their NPC police.
local function dress(target, g)
    local desc = g.desc

    -- 'off' and 'custom' both silence core's NPC heat; 'custom' just means
    -- the mode brings its own law (chase's AI units). 'ambient' is said out
    -- loud too, so a crashed round's suppression can't haunt this one.
    local suppress = desc.police == 'off' or desc.police == 'custom'
    TriggerClientEvent('core:heatSuppress', target, suppress)

    if desc.clock then TriggerClientEvent('core:clock', target, desc.clock) end
    if desc.respawn then TriggerClientEvent('core:respawnPolicy', target, desc.respawn) end

    TriggerClientEvent('core:gametype', target, {
        name  = g.name,
        label = g.label,
        ff    = desc.friendlyFire == nil and 'auto' or desc.friendlyFire,
    })
end

-- The client-side furniture, put back exactly as claimed. Kept free of Waits
-- so it also works from onResourceStop, where a thread would never run.
local function restore(g)
    if g.desc.clock then TriggerClientEvent('core:clock', -1) end
    if g.desc.respawn then TriggerClientEvent('core:respawnPolicy', -1, { kind = 'off' }) end

    TriggerClientEvent('core:heatSuppress', -1, false)
    TriggerClientEvent('core:gametype', -1) -- clients drop teams and put friendly fire back to off

    Teams.clear()
    Population.clear()
end

-- `dying` = core itself is stopping: run inline (a thread would never get a
-- turn) and skip the world release - the claim ledger dies with core anyway.
local function endRound(g, reason, dying)
    if active ~= g then return end

    active, endsAt = nil, nil
    session = session + 1

    local function finish()
        local hold = runHook(g, 'OnEnd', reason) == 'hold'

        restore(g)
        TriggerClientEvent('core:feed', -1, ('~y~%s~s~ round over - %s.'):format(g.label, reason))
        print(('[core] gametype %s ended (%s)'):format(g.name, reason))

        if hold or dying then return end

        -- The world claim waits a beat so the end card plays out before the
        -- default stack comes back - and not at all if something else has
        -- taken the stage in the gap.
        Wait(RELEASE_GRACE_MS)
        if active then return end

        WorldClaim.release()
    end

    if dying then finish() else CreateThread(finish) end
end

local function startRound(g, source)
    if active then
        return reply(source, ('%s is already running - /%s stop first.'):format(active.label, active.name))
    end

    local players = GetPlayers()
    local need    = g.desc.minPlayers or 1
    if #players < need then
        return reply(source, ('%s needs at least %d players.'):format(g.label, need))
    end

    active  = g
    session = session + 1
    local mine = session

    -- All the actual work lives in a thread: starting a round streams events
    -- and may one day wait on things, and this path is reachable from export
    -- callers - the same cannot-yield trap modes.lua documents.
    CreateThread(function()
        -- The stage: nothing else running, the streets as asked. 'alive' is
        -- the default and the weakest claim, so it is not worth registering -
        -- only quieter streets are.
        WorldClaim.claim(g.resource)
        if g.desc.population == 'empty' or g.desc.population == 'sparse' then
            Population.set(g.desc.population)
        end

        Teams.build(g.desc.teams, players)

        for _, p in ipairs(players) do
            local src = tonumber(p)
            if src then dress(src, g) end
        end

        runHook(g, 'OnStart')

        endsAt = g.desc.roundSeconds and (GetGameTimer() + g.desc.roundSeconds * 1000) or nil
        print(('[core] gametype %s started by %s'):format(g.name, g.resource))

        -- The heartbeat: the mode's OnTick at ~1Hz, and the framework's own
        -- whistle when the round clock runs out.
        while active == g and session == mine do
            Wait(1000)
            if active ~= g or session ~= mine then break end

            runHook(g, 'OnTick')

            if endsAt and GetGameTimer() >= endsAt then
                endRound(g, 'time')
            end
        end
    end)
end

-- ===== exports =====

exports('RegisterGametype', function(name, desc)
    if type(name) ~= 'string' or name == '' or type(desc) ~= 'table' then
        print('[core] RegisterGametype wants (name, descriptor table)')
        return false
    end

    -- Re-registering is routine - it is what a mode does every time it (or
    -- core) restarts - so this refreshes rather than refuses.
    registry[name] = {
        name     = name,
        label    = desc.label or name,
        resource = GetInvokingResource() or GetCurrentResourceName(),
        desc     = desc,
        hooks    = desc.hooks or {},
        live     = true,
    }

    -- The framework owns the chat command. Registered once per name and the
    -- closure reads the registry, so a mode restart never stacks handlers.
    if not commands[name] then
        commands[name] = true

        RegisterCommand(name, function(source, args)
            local g = registry[name]
            if not g then return end

            if not g.live then
                -- The mode's resource is stopped (another mode's world claim,
                -- usually). Start it; it re-registers on the way up.
                if GetResourceState(g.resource) ~= 'started' then StartResource(g.resource) end
                return reply(source, ('%s is waking up - give it a second and try again.'):format(g.label))
            end

            local action = args[1] or 'start'
            if action == 'start' then
                startRound(g, source)
            elseif action == 'stop' then
                if active ~= g then return reply(source, g.label .. ' is not running.') end
                endRound(g, 'stopped')
            else
                reply(source, ('usage: /%s start|stop'):format(name))
            end
        end, false)
    end

    return true
end)

-- A mode's own win condition ends the round; the reason lands in OnEnd.
exports('EndGametype', function(reason)
    if not active then return false end
    endRound(active, tostring(reason or 'ended'))
    return true
end)

exports('listGametypes', function()
    local out = {}
    for _, g in pairs(registry) do
        out[#out + 1] = { name = g.name, label = g.label, resource = g.resource, running = (active == g) }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end)

-- ===== lifecycle safety nets =====

-- A mode that stops - deliberately, by another claim, or face down in a stack
-- trace - must never leave the world claimed, friendly fire on, or the clock
-- frozen.
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        -- Core itself going down (a hot reload, usually) takes the registry
        -- and any live round with it; the client restores go out inline.
        if active then endRound(active, 'core-stopped', true) end
        return
    end

    for _, g in pairs(registry) do
        if g.resource == resource then
            g.live = false
            if active == g then endRound(g, 'resource-stopped') end
        end
    end
end)

-- The same "client is up, tell me the truth" knock that world.lua answers
-- with the population. A player joining mid-round gets the whole stage -
-- heat, clock, respawn, a team - and the mode gets told; a client that only
-- rebooted (core hot reload) is re-dressed and keeps its team.
AddEventHandler('core:worldReady', function()
    local src = source
    if not src or src <= 0 then return end
    if not active then return end

    local g     = active
    local isNew = Teams.get(src) == nil

    if isNew then Teams.assign(src) else Teams.reannounce(src) end
    dress(src, g)

    if isNew then runHook(g, 'OnPlayerJoin', src) end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if active then runHook(active, 'OnPlayerLeave', src) end
end)
