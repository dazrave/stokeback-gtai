-- Round director, and the man with the clipboard.
--
-- The world plumbing belongs to the gametype framework (core/server/
-- gametype.lua): claiming the map, muting NPC heat, the late-morning clock,
-- friendly fire and the /tri command itself all come off the descriptor at the
-- bottom of this file. The race state belongs to race.lua. What lives here is
-- the shape of the evening - the countdown, the transitions, the winner, the
-- sixty seconds everyone else gets, and the steward's running commentary.
local state = {
    phase        = 'idle', -- idle | countdown | racing | runout
    goesAt       = 0,      -- when the countdown reaches nought
    endsAt       = 0,      -- the main time limit
    runoutEndsAt = 0,      -- the post-winner window
    winner       = nil,
    armed        = false,  -- the REAL countdown is running (placement is done)
    token        = nil,    -- this race's identity, so a stale start thread
                           -- from a stopped race cannot arm the next one
    nagAt        = 0,      -- next time the steward may have opinions about last place
}

-- Which discipline comes where, for the straggler maths.
local LEG_INDEX = {}
for index, leg in ipairs(Config.LEG_ORDER) do LEG_INDEX[leg] = index end

local function mmss(ms)
    local seconds = math.floor((ms or 0) / 1000)
    return ('%d:%02d'):format(math.floor(seconds / 60), seconds % 60)
end

local function setState(next)
    local merged = {}
    for key, value in pairs(state) do merged[key] = value end
    for key, value in pairs(next) do merged[key] = value end
    state = merged
end

-- Said in chat AND printed. The console line matters: the map gate below is
-- the first thing anyone runs on a fresh clone, usually from the server
-- console with nobody connected, and a message only players can see would be
-- shouted into an empty stadium.
local function tell(message)
    TriggerClientEvent('chat:addMessage', -1, {
        color = { 120, 220, 120 },
        args  = { 'tri', message },
    })
    print('[tri] ' .. message)
end

local function note(src, message)
    TriggerClientEvent('tri:note', src, message)
end

local function pick(list)
    if not list or #list == 0 then return nil end
    return list[math.random(#list)]
end

-- ===== the map gate =====
-- Zero coordinates are tagged and a coordinate may never be guessed, so the
-- mode ships complete and refuses to start a race until the tag board has
-- caught up. This is the message that does the refusing, and it is the whole
-- user manual for tagging the course.
local function refuseUntagged(gaps)
    tell('Not yet - the Stokeback Triathlon has no course. Nothing on this list is tagged:')

    for _, gap in ipairs(gaps) do
        tell(('  %s: %d tagged, need %d to race (%d for the real thing) - %s'):format(
            gap.label, gap.have, gap.min, gap.want, gap.tag))
    end

    tell('Tag them at https://sbm.dazrave.uk/tag under gametype "the-stokeback-triathlon".')
    tell('The NOTE field is what the build reads, so number them in course order. Then /tri start.')
end

-- ===== the round, as the framework sees it =====

-- OnStart. The framework has already claimed the map, muted the police, set
-- the clock and given every racer their own team by the time this runs.
local function onStart()
    local gaps = TriCourse.missing()
    if #gaps > 0 then
        refuseUntagged(gaps)
        return exports.core:EndGametype('untagged')
    end

    local players = GetPlayers()
    if #players < Config.round.MIN_PLAYERS then
        tell(('Need %d on the start line. A race with nobody in it is just weather.'):format(
            Config.round.MIN_PLAYERS))
        return exports.core:EndGametype('short-handed')
    end

    -- Tonight's line. One seed per race, decided here and sent to every
    -- client, because the course has to flatten to the SAME ordered list
    -- everywhere - a client rolling its own would claim checkpoint 7 while
    -- the server was holding a different checkpoint 7.
    local seed = (Config.variation and Config.variation.ENABLED)
        and math.random(1, 999) or nil

    local built = TriCourse.build(nil, seed)
    if not built or not built.start then
        tell('The course built empty. Check Config.courses in config.lua.')
        return exports.core:EndGametype('untagged')
    end

    TriRace.begin(built, players)

    local now   = GetGameTimer()
    local token = {} -- unique per race: a table only ever equals itself

    -- A fresh table, NOT setState: a key written as nil in a constructor is
    -- simply absent, so a merge would quietly keep last race's winner - and
    -- the second race of the night would open in the sixty second finish
    -- window with a winner nobody had beaten. Chase paid for this lesson once
    -- already (#52); nobody needs to pay for it twice.
    state = {
        phase        = 'countdown',
        -- Provisional, and deliberately long: the real countdown starts below
        -- once everybody has actually been placed on the line. Racers are
        -- teleported 1.5s from here and a client can spend another few seconds
        -- waiting for collision, so counting from this moment would have the
        -- countdown most of the way through before anyone could see it.
        goesAt       = now + 120000,
        endsAt       = now + 120000 + Config.round.ROUND_LENGTH_S * 1000,
        runoutEndsAt = 0,
        winner       = nil,
        armed        = false,
        token        = token,
        nagAt        = 0,
    }

    CreateThread(function()
        Wait(1500) -- let the teams land before anyone gets moved

        for _, src in ipairs(players) do
            local id    = tonumber(src)
            local racer = id and TriRace.get(id)

            if racer then
                TriggerClientEvent('tri:course', id, {
                    course = built.name,
                    seed   = built.seed, -- tonight's line, so every client
                                         -- flattens the same course we did
                    label  = built.label,
                    slot   = racer.slot,
                    start  = built.start,
                    field  = #players,
                    hold   = true, -- frozen on the line until the countdown ends
                })
            end
        end

        -- Everyone is stood on the line. NOW start counting, so the number on
        -- screen is the whole countdown rather than whatever was left of it.
        Wait(Config.round.READY_S * 1000)

        -- The token check matters: this thread slept through six-odd seconds
        -- in which the race could have been stopped AND a new one started,
        -- and arming somebody else's countdown early would start their race
        -- while its racers were still being placed.
        if state.phase == 'countdown' and state.token == token then
            local from = GetGameTimer()
            setState({
                armed  = true,
                goesAt = from + Config.round.COUNTDOWN_S * 1000,
                endsAt = from + (Config.round.COUNTDOWN_S + Config.round.ROUND_LENGTH_S) * 1000,
            })
        end
    end)

    tell(('%s. %d on the start line.'):format(built.label, #players))
    for _, line in ipairs(Config.flavour.BRIEFING) do tell(line) end

    -- Which way we are going tonight, said out loud: a course that quietly
    -- changed would read as a bug, and quoting the seed means "that was
    -- different last time" is a settleable argument rather than an eternal
    -- one. The detour line tells them the one difference they can feel.
    local V = Config.variation
    if seed and V then
        if V.ANNOUNCE then tell(V.ANNOUNCE:format(seed)) end

        local detour = false
        for _, waypoint in ipairs(built.waypoints) do
            if waypoint.coords and waypoint.coords.name
                and waypoint.coords.name:find('past the pub') then detour = true end
        end

        local line = detour and V.DETOUR_IN or V.DETOUR_OUT
        if line then tell(line) end
    end
end

-- OnTick, ~1Hz from the framework while the round is live.
local function onTick()
    if state.phase == 'idle' then return end

    local now = GetGameTimer()

    if state.phase == 'countdown' and state.armed and now >= state.goesAt then
        setState({ phase = 'racing' })
        TriRace.markStart() -- times and splits measured from GO, not from setup
        TriggerClientEvent('tri:go', -1)
        tell(Config.flavour.GO_LINE)
    end

    local remaining = math.max(0, math.ceil((state.endsAt - now) / 1000))
    local status    = TriRace.publish()

    status.phase     = state.phase
    status.remaining = remaining
    -- nil until the real countdown is armed: the provisional two-minute
    -- placeholder on screen read as a broken race. The HUD shows the
    -- steward's hold line instead.
    status.countdown = state.armed
        and math.max(0, math.ceil((state.goesAt - now) / 1000)) or nil
    status.winner    = state.winner
    status.runout    = state.phase == 'runout'
        and math.max(0, math.ceil((state.runoutEndsAt - now) / 1000)) or nil

    TriggerClientEvent('tri:status', -1, status)

    -- The steward's opinions about last place (flavour.STRAGGLER): once the
    -- race has been on a while and the back marker is a whole discipline or
    -- more behind the front, they get a mention. Racing only - the runout
    -- window is already its own kind of pressure.
    local S = Config.flavour.STRAGGLER
    if S and state.phase == 'racing'
        and (now - state.goesAt) >= (S.AFTER_S or 240) * 1000
        and now >= state.nagAt then

        local standings = TriRace.standings()
        local leader, last = standings[1], standings[#standings]

        local behind = (leader and last and leader ~= last
            and not last.finished and not last.dnf)
            and (LEG_INDEX[leader.leg] or 1) - (LEG_INDEX[last.leg] or 1) or 0

        if behind >= (S.LEGS_BEHIND or 1) then
            setState({ nagAt = now + (S.EVERY_S or 90) * 1000 })

            local legCfg = Config.legs[last.leg] or {}
            tell((pick(S.LINES) or '%s is still on the %s leg.'):format(
                last.name,
                (legCfg.LABEL or last.leg):lower(),
                math.floor((now - state.goesAt) / 60000)))
        else
            setState({ nagAt = now + 10000 }) -- close race; look again shortly
        end
    end

    -- The finish window: it shuts on the clock, or early if there is simply
    -- nobody left out on the course.
    if state.phase == 'runout' then
        if now >= state.runoutEndsAt or TriRace.stillRacing() == 0 then
            exports.core:EndGametype('finished')
        end
        return
    end

    if state.phase == 'racing' and remaining <= 0 then
        exports.core:EndGametype('time')
    end
end

-- The scoreboard, read out. Finishers in order and on the clock, then - the
-- scope's fallback when nobody gets round - everybody else ranked by how far
-- they actually got, which race.lua has already sorted by discipline, then
-- checkpoint, then how close they were to the next one.
local function readOutStandings(standings, timeUp)
    for index, entry in ipairs(standings) do
        if entry.finished then
            tell(('  %d. %s - %s'):format(
                entry.place or index, entry.name, mmss(entry.time)))
        elseif timeUp then
            tell(('  %d. %s - still on %s when it stopped'):format(
                index, entry.name, TriCourse.describe(entry.waypoint)))
        else
            tell(('  %d. %s - DNF on %s'):format(
                index, entry.name, TriCourse.describe(entry.waypoint)))
        end
    end
end

-- OnEnd. Every road out of a race comes through here, whatever ended it.
local function onEnd(reason)
    -- The two non-races, handled before anything else: onStart refused before
    -- a race existed, so there is nothing to tear down. Take the world claim
    -- back immediately rather than leaving infected and pint stopped for the
    -- framework's end-card grace over a race that never happened.
    if reason == 'untagged' or reason == 'short-handed' then
        exports.core:releaseWorld()
        return 'hold'
    end

    if state.phase == 'idle' then return end

    local FRAMEWORK_REASONS = { time = 'time', stopped = 'abandoned' }
    local result = FRAMEWORK_REASONS[reason] or reason

    setState({ phase = 'idle' })

    -- Torn down by force (this resource or core going down): no drama, just
    -- make sure the next registration starts from idle and no client is left
    -- holding a bike it spawned. The ledger sweep runs inline and immediately
    -- - there may be no client left alive to do it kindly.
    if reason == 'resource-stopped' or reason == 'core-stopped' then
        TriggerClientEvent('tri:end', -1, result, nil)
        TriRace.clear()
        TriRace.binAll()
        return
    end

    -- A DNF is what happens when the finish WINDOW shuts on you. Running out
    -- of the twenty minute limit is not a DNF, it is a race that never had a
    -- winner, and the scope scores that one on progress instead.
    local timeUp = (result == 'time')
    local dnf = (result == 'finished' and Config.round.DNF_ON_WINDOW_END)
        and TriRace.dnfRemaining() or {}

    local standings = TriRace.standings()

    if result == 'finished' then
        tell(('%s wins the Stokeback Triathlon.'):format(state.winner or '?'))
    elseif timeUp then
        tell(Config.flavour.TIME_LINE)
        if not TriRace.anyFinished() then tell(Config.flavour.NOBODY_FINISHED) end
    elseif result == 'abandoned' then
        tell('Race abandoned. The steward is going for a pint.')
    end

    readOutStandings(standings, timeUp)

    for _, name in ipairs(dnf) do
        local line = pick(Config.flavour.DNF_LINES) or '%s: DNF.'
        tell(line:format(name, name))
    end

    -- The discipline awards (flavour.AWARDS): fastest split per leg, read out
    -- only for rounds that actually raced - an abandoned race gets no medals.
    if result == 'finished' or timeUp then
        local fastest = TriRace.fastest()
        for _, leg in ipairs(Config.LEG_ORDER) do
            local best = fastest[leg]
            local line = best and Config.flavour.AWARDS and Config.flavour.AWARDS[leg]
            if line then tell(line:format(best.name, mmss(best.ms))) end
        end
    end

    TriggerClientEvent('tri:end', -1, result, state.winner, standings)
    TriRace.clear()

    -- The ledger sweep, a beat later: the clients get first go, so the gentle
    -- fade can put a still-flying pilot down kindly before their aeroplane
    -- stops existing. Whatever a leaver or a borrowed bike left behind, the
    -- server bins itself - unless a new race has already begun, in which case
    -- its begin() has swept the ledger and these are ITS vehicles now.
    CreateThread(function()
        Wait(4000)
        if not TriRace.course() then TriRace.binAll() end
    end)
end

-- ===== what the clients tell us =====
-- Every handler treats its client as a witness, never as an authority: race.lua
-- checks identity, order, the server's own read of where that ped actually is,
-- and what it is sitting in.

-- Refusals not worth saying out loud: order and distance are the client and
-- the server disagreeing by a metre, which happens constantly and means
-- nothing. Being in the wrong thing entirely is the one a racer needs telling.
local QUIET_REFUSALS = {
    ['out of order']      = true, ['not actually there'] = true,
    ['already done']      = true, ['not racing']         = true,
    ['no course']         = true, ['no such checkpoint'] = true,
}

RegisterNetEvent('tri:reached', function(index)
    local src = source
    if state.phase ~= 'racing' and state.phase ~= 'runout' then return end

    -- On success `detail` is the event ('advanced' | 'leg' | 'finished'); on
    -- refusal it is the reason.
    local ok, detail, waypoint = TriRace.claim(src, tonumber(index) or 0)

    if not ok then
        if detail and not QUIET_REFUSALS[detail] then
            note(src, ('~y~That one wants you %s.'):format(detail))
        end
        return
    end

    if detail == 'finished' then
        local racer = TriRace.get(src)
        if not racer then return end

        local place = racer.position or 1

        if place == 1 then
            setState({
                phase        = 'runout',
                winner       = racer.name,
                runoutEndsAt = GetGameTimer() + Config.round.FINISH_WINDOW_S * 1000,
            })

            TriggerClientEvent('tri:winner', -1, racer.name, Config.round.FINISH_WINDOW_S)
            tell((pick(Config.flavour.WINNER_LINES) or '%s wins.'):format(racer.name))
        else
            local line = Config.flavour.FINISH_LINES[place]
            tell(line and line:format(racer.name)
                or Config.flavour.FINISH_DEFAULT:format(racer.name, place .. 'th'))
        end

        -- The photo finish (flavour.PHOTO): close enough behind the previous
        -- finisher and it gets the full ceremony - which includes second
        -- pipping first, the classic.
        local P = Config.flavour.PHOTO
        if P and racer.gapMs and racer.gapTo
            and racer.gapMs <= (P.MARGIN_S or 1.0) * 1000 then

            local gap = racer.gapMs / 1000.0
            TriggerClientEvent('tri:photo', -1, racer.gapTo, racer.name, gap)

            local line = pick(P.LINES)
            if line then tell(line:format(racer.gapTo, racer.name, gap)) end
        end

        return
    end

    local racer = TriRace.get(src)
    if not racer then return end

    -- The line-up goes out as soon as the transition becomes the NEXT thing
    -- they are heading for, so the bikes are sat waiting as they come over the
    -- last rise rather than materialising under their nose when they arrive.
    -- One line-up per racer per leg (race.lua keeps that honest), and the
    -- vehicle is put down in front of them, never under them: the scope is
    -- explicit that racers physically get on the thing.
    local upcoming = TriRace.waypoint(racer.at)
    if upcoming and upcoming.opens then
        local grant = TriRace.grantVehicle(src, 'transition', upcoming.opens)
        if grant then TriggerClientEvent('tri:garage', src, grant) end
    end

    if detail == 'leg' and waypoint and waypoint.opens then
        -- A late joiner, or anybody whose line-up never went out, gets it now.
        local catchUp = TriRace.grantVehicle(src, 'transition', waypoint.opens)
        if catchUp then TriggerClientEvent('tri:garage', src, catchUp) end

        local legCfg = Config.legs[waypoint.opens] or {}
        local line   = Config.flavour.LEG_LINES[waypoint.opens]
        if line then
            note(src, line:format(math.floor((legCfg.TARGET_S or 300) / 60)))
        end

        -- The split, read out (flavour.SPLITS): claiming a transition is what
        -- closes the discipline behind it, so this is the moment the time
        -- means something.
        local S = Config.flavour.SPLITS
        local split = racer.splits and racer.splits[waypoint.leg]
        if S and S.ANNOUNCE and split and S.LINES[waypoint.leg] then
            tell(S.LINES[waypoint.leg]:format(racer.name, mmss(split)))
        end
    end
end)

-- "My bike is in a lake." Granted by the server, on a cooldown, and only to
-- somebody who has actually reached a leg that has vehicles in it - otherwise
-- a runner could ask for a biplane on the start line.
RegisterNetEvent('tri:needVehicle', function()
    local src = source
    if state.phase ~= 'racing' and state.phase ~= 'runout' then return end

    local grant = TriRace.grantVehicle(src, 'recovery')
    if not grant then return end

    TriggerClientEvent('tri:garage', src, grant)

    local racer = TriRace.get(src)
    if racer then
        -- The steward keeps count (flavour.WROTE_OFF_MANY): from the Nth
        -- replacement, the polite lines give way to the ones with a number in.
        local M = Config.flavour.WROTE_OFF_MANY
        if M and racer.wrecks >= (M.AFTER or 3) then
            tell((pick(M.LINES) or '%s. Number %d.'):format(racer.name, racer.wrecks + 1))
        else
            tell((pick(Config.flavour.WROTE_OFF) or '%s needs another one.'):format(racer.name))
        end
    end
end)

-- The client reports what it spawned, by network id, so the server's own
-- ledger (race.lua) can sweep vehicles no client sweep will ever reach - a
-- disconnect mid-leg, a bike a mate borrowed and now owns. The report is
-- validated there: right model, and the reporter must own the entity.
-- The elastic, logged (client/banding.lua reports state CHANGES only). This
-- exists so "is the rubber banding actually working?" is answered from the
-- server log rather than from how somebody's evening felt - which is exactly
-- the question that went unanswered in nick for a fortnight while the boost
-- was silently doing nothing at all.
RegisterNetEvent('tri:bandState', function(engaged, value)
    local src = source
    if state.phase ~= 'racing' and state.phase ~= 'runout' then return end

    local racer = TriRace.get(src)
    if not racer then return end

    if engaged then
        print(('[tri] banding ON for %s (power +%.0f%%)'):format(
            racer.name, ((tonumber(value) or 1.0) - 1.0) * 100))
    else
        print(('[tri] banding off for %s'):format(racer.name))
    end
end)

RegisterNetEvent('tri:spawned', function(netId)
    local src = source
    if state.phase ~= 'racing' and state.phase ~= 'runout' then return end

    TriRace.registerVehicle(src, tonumber(netId))
end)

exports('getState', function()
    return {
        phase  = state.phase,
        winner = state.winner,
        racing = TriRace.stillRacing(),
    }
end)

-- ===== the declaration =====
-- Registered on every start of this resource AND of core: a core reboot wipes
-- the framework's registry, and a mode that doesn't put its hand back up stops
-- existing as far as /tri is concerned.
local function register()
    if state.phase ~= 'idle' then
        setState({ phase = 'idle' })
        TriRace.clear()
        TriRace.binAll()
        TriggerClientEvent('tri:end', -1, 'abandoned', nil)
        tell('Core rebooted mid-race - race abandoned. /tri start to go again.')
    end

    -- 'tri', not 'the-stokeback-triathlon': the framework turns the name into
    -- the chat command, and nobody is typing that twice a night.
    exports.core:RegisterGametype('tri', {
        label = 'The Stokeback Triathlon',

        -- Free for all: the framework gives every racer their own team, which
        -- is what a race is. Friendly fire OFF outright rather than 'auto' -
        -- with one team each, 'auto' would mean everybody can shoot everybody,
        -- and this is a sporting event. Ramming each other off a ridge remains
        -- entirely legal.
        teams        = 'ffa',
        friendlyFire = false,

        population   = Config.round.POPULATION,
        police       = Config.round.POLICE,
        clock        = Config.round.CLOCK,

        -- A race, not a death penalty: up quickly, and the client puts them
        -- back at the last checkpoint they actually reached with a fresh
        -- vehicle if the leg calls for one.
        respawn = {
            kind        = 'where-you-fell',
            delay       = Config.respawn.DELAY_S,
            downMessage = '~r~Down.~w~ Back to your last checkpoint in a moment.',
        },

        -- Backstop only: onTick calls time on its own clock, which starts when
        -- everyone has actually been placed on the line. This cap exists so a
        -- wedged race can never run forever.
        roundSeconds = Config.round.READY_S + Config.round.COUNTDOWN_S
            + Config.round.ROUND_LENGTH_S + Config.round.FINISH_WINDOW_S + 15,

        -- 0, not three, on purpose. The framework's floor would refuse before
        -- the map gate could speak, and "here is what to tag" is an answer you
        -- want from an empty console on a Tuesday, not from a full lobby on a
        -- Thursday. onStart enforces Config.round.MIN_PLAYERS itself.
        minPlayers = 0,

        hooks = {
            OnStart = onStart,
            OnTick  = onTick,
            OnEnd   = onEnd,

            -- Turned up late. They get put on the start line and race from
            -- scratch, which at ten minutes down is less a race than a jog,
            -- but it beats standing in a field watching.
            OnPlayerJoin = function(src)
                if state.phase == 'idle' then return end

                local built = TriRace.course()
                if not built then return end

                local racer = TriRace.add(src)
                if not racer then return end

                -- `hold` only while there is still a countdown to hold them
                -- for: a latecomer frozen on a line that has already gone
                -- would stand there for the rest of the race.
                TriggerClientEvent('tri:course', src, {
                    course = built.name,
                    seed   = built.seed, -- tonight's line, so every client
                                         -- flattens the same course we did
                    label  = built.label,
                    slot   = racer.slot,
                    start  = built.start,
                    field  = TriRace.stillRacing(),
                    hold   = state.phase == 'countdown',
                })

                tell(('%s has turned up late and is starting from the beginning. Bless.'):format(racer.name))
            end,

            OnPlayerLeave = function(src)
                if state.phase == 'idle' then return end

                -- Their vehicle outlives their connection otherwise: the
                -- entity migrates to whichever machine is nearest, and no
                -- client sweep will ever claim it.
                TriRace.binVehicles(src)
                TriRace.drop(src)

                -- Everyone who was still out there has gone home: there is
                -- nothing left to wait for. During the runout that is a
                -- finished race; before it, a race with nobody in it is just
                -- weather, and twenty minutes of it helps no one.
                if TriRace.stillRacing() == 0 then
                    if state.phase == 'runout' then
                        exports.core:EndGametype('finished')
                    else
                        exports.core:EndGametype('stopped')
                    end
                end
            end,
        },
    })
end

-- Belt and braces alongside the core-driven onEnd: nothing this mode's
-- clients spawned outlives this mode, whatever order things fall over in.
-- Same dual-cleanup shape as nick.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    TriRace.binAll()
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() or resource == 'core' then
        register()
    end
end)
