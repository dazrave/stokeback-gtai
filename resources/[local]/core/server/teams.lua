-- core: who is on whose side. FiveM has no team system, so every mode used to
-- hand-roll roles - chase invented "fugitive", infected invented "survivor" -
-- and none of them could share a friendly-fire rule. The gametype framework
-- (server/gametype.lua) asks for teams by SHAPE - 'ffa', 'coop', or an
-- explicit list - and this file deals players into them, remembers the
-- answer, and tells the clients.
--
-- The client half (client/teams.lua) stamps each player's team onto their ped
-- as a synced DECOR, because relationship groups do not sync between clients
-- (the oldest gotcha in AGENTS.md): a decor is the only team badge a
-- neighbour's machine can actually read.

Teams = {}

local teams    = {}   -- [teamId] = { id, label, colour, loadout, int, members = { [src]=true } }
local byPlayer = {}   -- [src] = teamId
local strategy = nil  -- 'ffa' | 'coop' | 'list' while a round has teams
local defs     = nil  -- the declared list, when strategy == 'list'

-- What leaves this file: a copy, never the live table, so no caller can
-- quietly rearrange the roster from outside.
local function publicDef(team)
    if not team then return nil end
    return {
        id      = team.id,
        label   = team.label,
        colour  = team.colour,
        loadout = team.loadout,
        int     = team.int,
    }
end

-- Broadcast, not whispered: friendly fire reads decors, but a mode's HUD or
-- server logic shouldn't have to - every client hears every change.
local function announce(src, team)
    TriggerClientEvent('core:teamChanged', -1, src, team and team.id or nil, publicDef(team))
end

local function put(src, teamId)
    local from = byPlayer[src] and teams[byPlayer[src]]
    if from then from.members[src] = nil end

    local to = teamId and teams[teamId]
    byPlayer[src] = to and teamId or nil
    if to then to.members[src] = true end

    announce(src, to)
end

-- `int` is the number stamped into the ped decor - it only has to be unique
-- within the round, and nonzero (zero means "no team" on the wire).
local function makeTeam(id, def, int)
    teams[id] = {
        id      = id,
        label   = def and def.label or id,
        colour  = def and def.colour,
        loadout = def and def.loadout,
        int     = int,
        members = {},
    }
    return teams[id]
end

function Teams.clear()
    teams, byPlayer, strategy, defs = {}, {}, nil, nil
end

function Teams.get(src)
    return byPlayer[tonumber(src)]
end

function Teams.active()
    return strategy ~= nil
end

-- A client that rebooted mid-round (core hot reload) lost its own answer;
-- say it again so the decor comes back.
function Teams.reannounce(src)
    src = tonumber(src)
    local team = byPlayer[src] and teams[byPlayer[src]]
    if team then announce(src, team) end
end

-- Deal the room into sides. `shape` comes straight off the gametype
-- descriptor: 'ffa' (every player their own team), 'coop' (one big one), or
-- an explicit list, split evenly at random. A listed team can opt out of the
-- deal with `assign = false` - chase's fugitive slot works like that, filled
-- by hand through SetTeam once the rota has spoken.
function Teams.build(shape, players)
    Teams.clear()
    shape = shape or 'coop'

    if shape == 'ffa' then
        strategy = 'ffa'
        for _, p in ipairs(players) do
            local src = tonumber(p)
            if src then
                -- 100 + server id: unique per player, never 0, and never
                -- colliding with a list round's small ints if one follows.
                makeTeam('p' .. src, { label = GetPlayerName(src) or ('#' .. src) }, 100 + src)
                put(src, 'p' .. src)
            end
        end
        return
    end

    if shape == 'coop' then
        strategy = 'coop'
        makeTeam('crew', { label = 'The Crew' }, 1)
        for _, p in ipairs(players) do
            local src = tonumber(p)
            if src then put(src, 'crew') end
        end
        return
    end

    strategy, defs = 'list', shape

    local dealable = {}
    for index, def in ipairs(shape) do
        local team = makeTeam(def.id, def, index)
        if def.assign ~= false then dealable[#dealable + 1] = team end
    end

    if #dealable == 0 then return end -- everything manual; SetTeam fills them

    -- Shuffle the room, deal round-robin: sides come out even (never off by
    -- more than one) and nobody can engineer a stack by joining in order.
    local pool = {}
    for _, p in ipairs(players) do
        local src = tonumber(p)
        if src then pool[#pool + 1] = src end
    end
    for i = #pool, 2, -1 do
        local j = math.random(i)
        pool[i], pool[j] = pool[j], pool[i]
    end

    for index, src in ipairs(pool) do
        put(src, dealable[((index - 1) % #dealable) + 1].id)
    end
end

-- A late joiner slots in wherever the numbers say: their own team in FFA, the
-- crew in co-op, the emptiest dealable side otherwise.
function Teams.assign(src)
    src = tonumber(src)
    if not src or not strategy then return nil end

    if strategy == 'ffa' then
        makeTeam('p' .. src, { label = GetPlayerName(src) or ('#' .. src) }, 100 + src)
        put(src, 'p' .. src)
    elseif strategy == 'coop' then
        put(src, 'crew')
    else
        local best, bestCount = nil, nil
        for _, def in ipairs(defs) do
            local team = teams[def.id]
            if team and def.assign ~= false then
                local count = 0
                for _ in pairs(team.members) do count = count + 1 end
                if not bestCount or count < bestCount then best, bestCount = team, count end
            end
        end
        if best then put(src, best.id) end
    end

    return byPlayer[src]
end

-- ===== exports =====
-- None of these yield, so they are safe as exports.

-- Manual placement, for the modes that pick somebody by name - chase moves
-- its fugitive here after the rota has spoken.
exports('SetTeam', function(src, teamId)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return false end
    if not teams[teamId] then return false end

    put(src, teamId)
    return true
end)

exports('GetTeam', function(src)
    return byPlayer[tonumber(src)]
end)

exports('GetTeamMembers', function(teamId)
    local team = teams[teamId]
    if not team then return {} end

    local out = {}
    for src in pairs(team.members) do out[#out + 1] = src end
    table.sort(out)
    return out
end)

exports('GetTeams', function()
    local out = {}
    for _, team in pairs(teams) do
        local def = publicDef(team)
        def.members = {}
        for src in pairs(team.members) do def.members[#def.members + 1] = src end
        table.sort(def.members)
        out[#out + 1] = def
    end
    table.sort(out, function(a, b) return (a.int or 0) < (b.int or 0) end)
    return out
end)

-- Leavers fall off the roster; telling the mode is the framework's job
-- (hooks.OnPlayerLeave in server/gametype.lua), not ours.
AddEventHandler('playerDropped', function()
    local src = source
    if byPlayer[src] then put(src, nil) end
end)
