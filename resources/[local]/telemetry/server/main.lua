-- Route telemetry sink. Every player's position lands here a few times a
-- minute, plus context marks from the game modes (mission stages, wipes,
-- chase rounds) and manual /tmark notes. One JSON line per record, one file
-- per server session, under this resource's folder.
--
-- The "learning" half happens offline: the files get pulled and analysed, and
-- spawn points, wreck placement, ambushes and event triggers get retuned to
-- the routes people actually take.
local session = os.date('%Y%m%d-%H%M%S')
local file    = ('data-%s.jsonl'):format(session)
local lines   = {}
local dirty   = false

local function append(record)
    lines[#lines + 1] = json.encode(record)
    dirty = true
end

RegisterNetEvent('telemetry:batch', function(samples)
    local source = source
    if type(samples) ~= 'table' then return end

    local name = GetPlayerName(source) or ('#' .. tostring(source))
    local now  = os.time()

    for _, sample in ipairs(samples) do
        if type(sample) == 'table' and type(sample.x) == 'number' then
            append({
                t = now, p = name,
                x = sample.x, y = sample.y, z = sample.z,
                s = sample.s, v = sample.v, d = sample.d,
            })
        end
    end
end)

-- Game modes stamp context with TriggerEvent('telemetry:mark', 'label').
AddEventHandler('telemetry:mark', function(label)
    append({ t = os.time(), mark = tostring(label) })
end)

-- Players can flag a moment by hand: /tmark that bridge chase was amazing
RegisterCommand('tmark', function(source, args)
    local note = table.concat(args, ' ')
    if note == '' then note = 'moment' end

    append({
        t    = os.time(),
        mark = 'player-note',
        p    = source > 0 and GetPlayerName(source) or 'console',
        note = note,
    })

    if source > 0 then
        TriggerClientEvent('chat:addMessage', source, {
            color = { 160, 160, 160 },
            args  = { 'telemetry', 'marked: ' .. note },
        })
    end
end, false)

local function flush()
    if not dirty then return end
    dirty = false
    SaveResourceFile(GetCurrentResourceName(), file, table.concat(lines, '\n') .. '\n', -1)
end

CreateThread(function()
    while true do
        Wait(20000)
        flush()
    end
end)

-- ===== clapperboard =====
-- One trigger that leaves a sync point in every recording at once: a white
-- screen flash (seen in every video angle), a beep (heard where game audio is
-- captured), and a logged marker at the exact time. The editor lines the
-- flashes up and every angle shares a zero point; audio tracks then align to
-- the logged time via wall clock. Run /clap at the top of the session - it also
-- fires once automatically when the first person turns up, so a session always
-- has at least one sync point.
local clapCount = 0

local function clap(reason)
    clapCount = clapCount + 1
    append({ kind = 'sync', t = os.time(), n = clapCount, why = reason or 'manual' })
    flush() -- persist the sync marker immediately, don't wait for the 20s flush
    TriggerClientEvent('telemetry:sync', -1, clapCount)
    TriggerClientEvent('chat:addMessage', -1, {
        color = { 245, 200, 66 },
        args  = { 'clap', ('CLAP #%d — sync marker logged'):format(clapCount) },
    })
    print(('[telemetry] clap #%d (%s) at %d'):format(clapCount, reason or 'manual', os.time()))
end

RegisterCommand('clap', function() clap('manual') end, false)

-- Fire the clap over HTTP, so a Stream Deck (or any one-button "go live" macro)
-- can trigger the sync without anyone typing a command in-game. LAN-only in
-- practice; a token keeps a stray browser request from setting it off.
--   http://<server-ip>:30120/telemetry/clap?key=<telemetry_clap_key>

-- ===== announcements from outside the game =====
-- The workshop daemon calls this to narrate the build loop in chat: an idea
-- was heard, a build is ready, a change just went live. Everyone playing sees
-- it without alt-tabbing, and it lands on camera, which is the point.
--   http://<server-ip>:30120/telemetry/say?key=<telemetry_say_key>&text=hello&colour=yellow

local COLOURS = {
    yellow = { 245, 200, 66 },
    green  = { 120, 255, 120 },
    red    = { 255, 120, 120 },
    blue   = { 120, 190, 255 },
    grey   = { 160, 160, 160 },
}

local function urldecode(text)
    text = text:gsub('+', ' ')
    return (text:gsub('%%(%x%x)', function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

-- Pull one parameter out of a query string. Values arrive percent-encoded.
local function query(path, name)
    local raw = path:match('[?&]' .. name .. '=([^&]*)')
    return raw and urldecode(raw) or nil
end

-- Route keys live in convars (set in secrets.cfg), never in source: this repo
-- is public, so a literal here is a key on the internet. An unset convar
-- disables its route outright - a fresh checkout exposes nothing until the
-- operator opts in.
local function keyed(path, name)
    local key = GetConvar(('telemetry_%s_key'):format(name), '')
    return key ~= '' and query(path, 'key') == key
end

-- ===== gametype switching =====
-- Every mode the crew can flip to, in one list: registered gametypes
-- (exports.core:listGametypes(), the framework's own scheme) plus the
-- legacy hand-rolled modes that never ported to it, plus a freeroam
-- pseudo-entry. This list IS the whitelist - POST /mode only ever
-- ExecuteCommands a string that came from an entry here, never
-- caller-supplied text.
--   http://<server-ip>:30120/telemetry/modes?key=<telemetry_mode_key>
--   http://<server-ip>:30120/telemetry/mode?key=<telemetry_mode_key>&name=<id>[&action=stop]
--
-- Deliberately self-contained rather than reusing modeState() further down
-- this file: that local is declared AFTER SetHttpHandler, so a closure built
-- here could not see it as an upvalue - the exact nil-upvalue trap
-- everyoneDown's comment below warns about.
local function exportedFlag(resource, field)
    local ok, state = pcall(function() return exports[resource].getState() end)
    return ok and type(state) == 'table' and state[field] and true or false
end

local function modeEntries()
    local entries = {}

    local ok, registered = pcall(function() return exports.core:listGametypes() end)
    if ok and type(registered) == 'table' then
        for _, g in ipairs(registered) do
            entries[#entries + 1] = {
                id = g.name, label = g.label,
                running = g.running and true or false,
                start = g.name .. ' start', stop = g.name .. ' stop',
            }
        end
    end

    -- Legacy modes never registered with core: a static entry each, with
    -- their real commands and a cheap read of their own exported state.
    entries[#entries + 1] = {
        id = 'infected', label = 'Zombie Horde',
        running = exportedFlag('infected', 'running'),
        start = 'horde start', stop = 'horde stop',
    }

    entries[#entries + 1] = {
        id = 'pint', label = 'The Campaign',
        running = exportedFlag('pint', 'active'),
        start = 'pint start', stop = 'pint stop',
    }

    -- Freeroam isn't a mode so much as the absence of one. resetgame is the
    -- big red button that actually gets everyone there; there's no separate
    -- stop for it - stopping freeroam just means picking something else.
    local anyRunning = false
    for _, e in ipairs(entries) do
        if e.running then anyRunning = true end
    end

    entries[#entries + 1] = {
        id = 'freeroam', label = 'Free Roam',
        running = not anyRunning,
        start = 'resetgame', stop = nil,
    }

    return entries
end

local function findModeEntry(id)
    for _, e in ipairs(modeEntries()) do
        if e.id == id then return e end
    end
    return nil
end

-- ===== free-roam flag =====
-- Clients get told when the server is in free roam (no mode running) so
-- free-roam-only perks can gate on it. Broadcast unconditionally on a slow
-- tick rather than on change: it also serves as the join-time sync, and at
-- this size there is nothing to save by being clever.
CreateThread(function()
    while true do
        local entry = findModeEntry('freeroam')
        TriggerClientEvent('telemetry:freeroam', -1, entry and entry.running or false)
        Wait(3000)
    end
end)

-- ===== who is who =====
-- The workshop pushes the list of people currently in the voice server. That
-- list IS the crew: nobody maintains a roster file, whoever turned up tonight
-- is tonight's lineup.
--
-- Players then claim which voice is theirs with /iam. That link is the whole
-- point: it joins "Rory said the thing" to "rorypicko was stood at the pier",
-- so an overheard idea can be filed with both halves of the story.
local crew    = {}   -- Mumble names currently in voice
local claimed = {}   -- [serverId] = Mumble name

local function crewList()
    if #crew == 0 then return 'nobody in voice yet' end
    return table.concat(crew, ', ')
end

local function tell(target, text, colour)
    TriggerClientEvent('chat:addMessage', target, {
        color = colour or COLOURS.blue,
        args  = { 'voice', text },
    })
end

local function promptUnclaimed()
    if #crew == 0 then return end

    for _, src in ipairs(GetPlayers()) do
        local id = tonumber(src)
        if not claimed[id] then
            tell(id, ('Who are you in voice? Type /iam <name> — %s'):format(crewList()))
        end
    end
end

-- /iam rory     - claim a voice. Matched loosely, because nobody wants to type
--                 an exact handle while being chased.
RegisterCommand('iam', function(source, args)
    if source == 0 then return end

    local wanted = (args[1] or ''):lower()
    if wanted == '' then
        tell(source, ('Usage: /iam <name> — in voice right now: %s'):format(crewList()))
        return
    end

    for _, name in ipairs(crew) do
        if name:lower():find(wanted, 1, true) then
            claimed[source] = name
            tell(source, ('You are %s. Ideas you shout will be filed under that name.'):format(name),
                 COLOURS.green)
            return
        end
    end

    tell(source, ('No "%s" in voice. Currently: %s'):format(wanted, crewList()), COLOURS.red)
end, false)

RegisterCommand('whoami', function(source)
    if source == 0 then return end
    tell(source, claimed[source]
        and ('You are %s in voice.'):format(claimed[source])
        or  ('You haven\'t claimed a voice yet. /iam <name> — %s'):format(crewList()))
end, false)

AddEventHandler('playerDropped', function()
    claimed[source] = nil
end)

-- Anything else that wants the mapping (telemetry snapshots, the workshop).
exports('getVoice', function(serverId) return claimed[serverId] end)
exports('getCrew', function() return crew end)

-- Latest ping per player. Declared up here, above the HTTP handler, so the
-- /players route captures this local and not a nil global - the same upvalue
-- trap everyoneDown's comment describes further down. Filled by
-- telemetry:ping in the live-positions section below.
local positions = {}

SetHttpHandler(function(req, res)
    local path = req.path or ''

    if path:find('^/roster') and keyed(path, 'say') then
        local names = query(path, 'names') or ''
        local fresh = {}

        for name in names:gmatch('[^,]+') do
            name = name:match('^%s*(.-)%s*$')
            if name ~= '' then fresh[#fresh + 1] = name end
        end

        crew = fresh

        -- Drop claims for anyone who has since left voice, so a stale name
        -- can't keep collecting somebody else's ideas.
        for id, name in pairs(claimed) do
            local present = false
            for _, live in ipairs(crew) do
                if live == name then present = true break end
            end
            if not present then claimed[id] = nil end
        end

        promptUnclaimed()

        res.writeHead(200, { ['Content-Type'] = 'text/plain' })
        res.send(('crew: %d\n'):format(#crew))
        return
    end

    if path:find('^/clap') and keyed(path, 'clap') then
        clap('streamdeck')
        res.writeHead(200, { ['Content-Type'] = 'text/plain' })
        res.send('clap fired\n')
        return
    end

    if path:find('^/say') and keyed(path, 'say') then
        local text = query(path, 'text')

        if not text or text == '' then
            res.writeHead(400, { ['Content-Type'] = 'text/plain' })
            res.send('no text\n')
            return
        end

        -- Chat is a shout, not a log: keep it to one readable line.
        text = text:sub(1, 240)

        TriggerClientEvent('chat:addMessage', -1, {
            color = COLOURS[query(path, 'colour') or 'yellow'] or COLOURS.yellow,
            args  = { 'workshop', text },
        })

        print(('[telemetry] say: %s'):format(text))
        res.writeHead(200, { ['Content-Type'] = 'text/plain' })
        res.send('said\n')
        return
    end

    -- Everyone currently on, as JSON, for tools outside the game (dashboards,
    -- overlays). Coords/heading come from the server's own entity view - under
    -- onesync that's live even before a player's first ping. Street/area only
    -- exist as client natives, so they're relayed from each player's latest
    -- telemetry:ping snapshot and are omitted until one lands.
    --   http://<server-ip>:30120/telemetry/players?key=<telemetry_players_key>
    if path:find('^/players') and keyed(path, 'players') then
        local players = {}

        for _, src in ipairs(GetPlayers()) do
            local ped = GetPlayerPed(src)

            -- No ped yet means still connecting; there's no position to report.
            if ped and ped ~= 0 then
                local pos  = GetEntityCoords(ped)
                local snap = positions[tonumber(src)]

                players[#players + 1] = {
                    src     = tonumber(src),
                    name    = GetPlayerName(src) or ('#' .. tostring(src)),
                    x       = math.floor(pos.x * 10) / 10,
                    y       = math.floor(pos.y * 10) / 10,
                    z       = math.floor(pos.z * 10) / 10,
                    heading = math.floor(GetEntityHeading(ped) * 10) / 10,
                    street  = snap and snap.street or nil,
                    area    = snap and snap.area or nil,
                }
            end
        end

        res.writeHead(200, { ['Content-Type'] = 'application/json' })
        -- json.encode renders an empty Lua table as '{}'; an empty server is
        -- still an array to the caller.
        res.send(#players > 0 and json.encode(players) or '[]')
        return
    end

    -- Every switchable mode, with which one is currently running.
    --   http://<server-ip>:30120/telemetry/modes?key=<telemetry_mode_key>
    if path:find('^/modes') and keyed(path, 'mode') then
        local list = {}
        for _, e in ipairs(modeEntries()) do
            list[#list + 1] = { id = e.id, label = e.label, running = e.running }
        end

        res.writeHead(200, { ['Content-Type'] = 'application/json' })
        res.send(json.encode(list))
        return
    end

    -- Switch the running mode. name is looked up against the SAME list
    -- /modes serves - never executed as raw text - so this can only ever
    -- fire a command an entry already carries.
    --   http://<server-ip>:30120/telemetry/mode?key=<telemetry_mode_key>&name=<id>[&action=stop]
    -- (checked after /modes on purpose: '/mode' is a prefix of '/modes')
    if path:find('^/mode') and keyed(path, 'mode') then
        local function respond(name, action)
            local entry = name and findModeEntry(name)

            if not entry then
                res.writeHead(400, { ['Content-Type'] = 'application/json' })
                res.send(json.encode({ ok = false, error = 'unknown mode' }))
                return
            end

            local command = (action == 'stop') and entry.stop or entry.start
            if not command then
                res.writeHead(400, { ['Content-Type'] = 'application/json' })
                res.send(json.encode({ ok = false, error = 'no ' .. tostring(action) .. ' action for ' .. entry.id }))
                return
            end

            print(('[telemetry] mode switch -> %s'):format(command))
            ExecuteCommand(command)

            res.writeHead(200, { ['Content-Type'] = 'application/json' })
            res.send(json.encode({ ok = true, executed = command }))
        end

        local qname   = query(path, 'name')
        local qaction = query(path, 'action') or 'start'

        if qname then
            respond(qname, qaction)
        else
            -- No name on the query string: fall back to a JSON body, same
            -- shape the scope-web proxy sends. Async - the response goes out
            -- from inside this callback, not the SetHttpHandler call itself.
            req.setDataHandler(function(body)
                local ok, data = pcall(json.decode, body or '')
                data = (ok and type(data) == 'table') and data or {}
                respond(data.name, data.action or qaction)
            end)
        end
        return
    end

    res.writeHead(403, { ['Content-Type'] = 'text/plain' })
    res.send('nope\n')
end)

CreateThread(function()
    while true do
        Wait(3000)
        if clapCount == 0 and #GetPlayers() > 0 then
            Wait(2000)
            clap('auto-session-start')
            return
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    flush()
end)

-- /resetgame - the big red button: stop every mode, restart the game
-- resources (which sweeps their spawned entities), bin leftover vehicles and
-- respawn everyone fresh. Square one.
--
-- Uses StopResource/StartResource, NOT ExecuteCommand('ensure ...'): a
-- resource has no permission for the ensure/start console commands, so that
-- silently stopped the game modes and never brought them back.
-- Somewhere different every reset, but the crew always lands together: one
-- random spot for the whole server, everyone within a few metres of it.
local RESET_SPAWNS = {
    { x = 215.0,   y = -810.0,  z = 30.7,  h = 340.0 }, -- Legion Square
    { x = -1183.0, y = -1494.0, z = 4.4,   h = 120.0 }, -- Vespucci Beach
    { x = 1961.0,  y = 3740.0,  z = 32.3,  h = 210.0 }, -- Sandy Shores
    { x = -292.0,  y = 6256.0,  z = 31.5,  h = 45.0  }, -- Paleto Bay
    { x = 302.0,   y = 180.0,   z = 104.0, h = 160.0 }, -- Vinewood Hills
    { x = -1037.0, y = -2737.0, z = 20.2,  h = 330.0 }, -- LSIA
    { x = 1687.0,  y = 4929.0,  z = 42.1,  h = 190.0 }, -- Grapeseed
    { x = -3172.0, y = 1077.0,  z = 20.8,  h = 90.0  }, -- Chumash
    { x = 1070.0,  y = -750.0,  z = 58.0,  h = 270.0 }, -- Mirror Park
    { x = -1850.0, y = -1231.0, z = 13.0,  h = 30.0  }, -- Del Perro Pier
}

-- ===== square one =====
-- The world half of /resetgame, on its own so a mode can call it after a total
-- wipe without also restarting every resource - restarting them mid-wipe would
-- tear down the very mode that is trying to start itself again.
local function resetWorld()
    TriggerClientEvent('telemetry:clearworld', -1)
    Wait(1200)

    local at = RESET_SPAWNS[math.random(#RESET_SPAWNS)]
    for index, src in ipairs(GetPlayers()) do
        TriggerClientEvent('telemetry:respawn', tonumber(src), at, index)
    end
end

exports('resetWorld', function()
    CreateThread(resetWorld)
end)

RegisterCommand('resetgame', function()
    TriggerClientEvent('chat:addMessage', -1, {
        color = { 255, 120, 120 },
        args  = { 'server', 'Resetting everything back to square one...' },
    })

    CreateThread(function()
        StopResource('pint')
        StopResource('chase')
        Wait(500)

        -- Restarting infected also takes its dependents down, hence the order.
        StopResource('infected')
        StopResource('squadmate')   -- harmless if it isn't running
        Wait(800)

        StartResource('infected')
        -- Squadmates are off (#18). Starting it here would resurrect them a
        -- few seconds after every reset, which looks like the toggle failing.
        -- Re-enable in server.cfg AND uncomment this line together.
        -- StartResource('squadmate')
        Wait(1200)

        -- Bin orphaned vehicles before the modes come back, so nothing spawns
        -- on top of a leftover from the last round.
        TriggerClientEvent('telemetry:clearworld', -1)
        Wait(1500)

        StartResource('pint')
        StartResource('chase')
        Wait(1500)

        local at = RESET_SPAWNS[math.random(#RESET_SPAWNS)]

        for index, src in ipairs(GetPlayers()) do
            TriggerClientEvent('telemetry:respawn', tonumber(src), at, index)
        end

        TriggerClientEvent('chat:addMessage', -1, {
            color = { 120, 255, 120 },
            args  = { 'server', 'Reset complete. /pint start lastorders | /horde start | /chase start' },
        })
    end)
end, false)


-- ===== live positions + periodic state snapshots =====
-- The positions relay also drives the mate radar (it was lost in an earlier
-- rewrite, so the radar has been dead). On top of it, a state snapshot every
-- few seconds records the whole board - mode, mission, wave, and where everyone
-- was - so an overheard "the zombies are too fast" can be filed alongside the
-- exact situation that prompted it. (The `positions` table itself is declared
-- above the HTTP handler, which also reads it.)

RegisterNetEvent('telemetry:ping', function(pos)
    local source = source
    if type(pos) ~= 'table' or type(pos.x) ~= 'number' then return end

    positions[source] = {
        id = source, name = GetPlayerName(source) or ('#' .. tostring(source)),
        x = pos.x, y = pos.y, z = pos.z,
        v = pos.v and true or false,
        d = pos.d and true or false,
        -- Everything an overheard line needs to make sense a week later.
        street = pos.street, area = pos.area,
        weapon = pos.weapon, ammo = pos.ammo, clip = pos.clip,
        hp = pos.hp, armour = pos.armour, skin = pos.skin,
        car = pos.car, speed = pos.speed,
        at = os.time(),
    }
end)

AddEventHandler('playerDropped', function()
    positions[source] = nil
end)

-- True when there are players and every one of them is down. Positions carry a
-- dead flag and refresh every second, so this is current rather than a guess;
-- stale entries are ignored outright so a disconnect can't look like a corpse.
--
-- Lives BELOW the positions table on purpose. It used to sit sixty lines above
-- it, where the closure captured a global `positions` (nil) instead of the
-- local - so every call errored, and infected's "everyone died, go again"
-- check silently never worked. The nil-upvalue trap: luac can't see it, and it
-- only shows at runtime.
exports('everyoneDown', function()
    local now, seen = os.time(), 0

    for _, p in pairs(positions) do
        if (now - (p.at or 0)) < 10 then
            seen = seen + 1
            if not p.d then return false end
        end
    end

    return seen > 0
end)

-- Matches the clients' ping rate: relaying slower than they report just adds
-- staleness on top of theirs. The list is a handful of numbers per player, so
-- at a dozen players this is nothing next to the position stream FiveM is
-- already sending.
local MATES_MS = 1000

CreateThread(function()
    while true do
        Wait(MATES_MS)

        local list = {}
        for _, p in pairs(positions) do
            list[#list + 1] = { id = p.id, name = p.name, x = p.x, y = p.y, z = p.z }
        end

        if #list > 0 then
            TriggerClientEvent('telemetry:mates', -1, list)
        end
    end
end)

-- Ask another resource for its state without caring whether it is running.
local function modeState(resource, fn)
    local ok, result = pcall(function()
        return exports[resource][fn]()
    end)
    return ok and result or nil
end

CreateThread(function()
    while true do
        Wait(8000)

        local now     = os.time()
        local players = {}

        for _, p in pairs(positions) do
            if (now - (p.at or 0)) < 20 then
                players[#players + 1] = {
                    name = p.name,
                    -- The voice name, when they've claimed one. This is what
                    -- lets an overheard line be tied to where its speaker was.
                    voice = claimed[p.id],
                    x = math.floor(p.x * 10) / 10,
                    y = math.floor(p.y * 10) / 10,
                    z = math.floor(p.z * 10) / 10,
                    v = p.v, d = p.d,
                    street = p.street, area = p.area,
                    weapon = p.weapon, ammo = p.ammo, clip = p.clip,
                    hp = p.hp, armour = p.armour,
                    car = p.car, speed = p.speed,
                }
            end
        end

        if #players > 0 then
            append({
                t       = now,
                kind    = 'state',
                horde   = modeState('infected', 'getState'),
                mission = modeState('pint', 'getState'),
                chase   = modeState('chase', 'getState'),
                players = players,
            })
        end
    end
end)


-- ===== spawn together =====
-- In free roam, dying used to drop you at a random map spawn, which with a
-- group means a five minute drive back to whoever you were with. Now you land
-- next to somebody. Modes are left alone: they place you deliberately
-- (checkpoints, scatter stages, chase roles) and must not be second-guessed.
local function anyModeRunning()
    local mission = modeState('pint', 'getState')
    if mission and mission.active then return true end

    local chase = modeState('chase', 'getState')
    if chase and chase.phase and chase.phase ~= 'idle' then return true end

    local horde = modeState('infected', 'getState')
    if horde and horde.engaged then return true end

    return false
end

RegisterNetEvent('telemetry:needSpawnBuddy', function()
    local source = source
    if anyModeRunning() then return end

    local now     = os.time()
    local options = {}

    for id, p in pairs(positions) do
        -- Somebody alive, on their feet, and reporting recently enough that
        -- the position isn't where they were five minutes ago.
        if id ~= source and not p.d and (now - (p.at or 0)) < 30 then
            options[#options + 1] = p
        end
    end

    if #options == 0 then return end   -- first one in; a normal spawn is fine

    local buddy = options[math.random(#options)]
    TriggerClientEvent('telemetry:spawnNear', source, {
        x = buddy.x, y = buddy.y, z = buddy.z, name = buddy.name,
    })
end)
