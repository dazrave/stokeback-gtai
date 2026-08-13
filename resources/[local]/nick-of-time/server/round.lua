-- Round director. The server owns the phase, the clock, who the robber is and
-- what the police are told; clients own eyes, wheels and the bag prompts.
--
-- The world plumbing belongs to the gametype framework (core/server/
-- gametype.lua): claiming the city, muting NPC heat, the dusk clock, friendly
-- fire and the /nick command itself all come off the descriptor at the bottom
-- of this file. What lives here is the drama - the rota, the endings, and the
-- one voice that announces things.
local state = {
    phase       = 'idle', -- idle | setup | active
    robber      = nil,    -- server id
    robberName  = nil,
    startsAt    = 0,
    endsAt      = 0,
    lastTick    = 0,
    pos         = nil,    -- where the server last read him; never published as-is
    copSpawn    = nil,    -- this round's muster point, kept for late joiners
    lastContact = 'cold', -- for control's radio commentary
    radioAt     = 0,      -- next moment control is allowed to speak
    heliOffered = false,  -- control has told them the favour is available
    lastStars   = 0,      -- for control's star-up commentary
}

local function setState(next)
    local merged = {}
    for key, value in pairs(state) do merged[key] = value end
    for key, value in pairs(next) do merged[key] = value end
    state = merged
end

-- Said in chat AND printed. The console line matters: the map gate below is
-- the first thing anyone runs on a fresh clone, usually from the server
-- console with nobody connected, and a message only players can see would be
-- shouted into an empty room.
local function tell(message)
    TriggerClientEvent('chat:addMessage', -1, {
        color = { 245, 200, 66 },
        args  = { 'nick', message },
    })
    print('[nick] ' .. message)
end

-- The robber's position as the SERVER sees it, fresh off his synced ped. The
-- drain, the stash, the dive and the arrest all measure against this rather
-- than against anything a client sends - coords in an event are the one thing
-- a modded client could lie about, and the scope asks for exactly this
-- ("server-authoritative position for all detection maths").
local function robberPos()
    if not state.robber then return nil end

    local ped = GetPlayerPed(state.robber)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end

    local at = GetEntityCoords(ped)
    return { x = at.x, y = at.y, z = at.z }
end

-- Whatever he is sat in, as the server sees it. A loot car's value hangs off
-- this, so like his position it is read here rather than reported by him.
local function robberVehicle()
    if not state.robber then return nil end

    local ped = GetPlayerPed(state.robber)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end

    local vehicle = GetVehiclePedIsIn(ped)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end

    return vehicle
end

-- ===== control, on the radio =====
-- Police ears only, and dry on purpose. The robber never hears any of it:
-- being told "they have lost you" would replace the pressure feeling with a
-- fact, and the feeling is the game.
local function epithet()
    local list = Config.flavour.EPITHETS
    if not list or #list == 0 then return 'the suspect' end

    -- Seeded once per session: control settles on a name for him on round
    -- one and sticks to it all evening, which is funnier than variety.
    return list[1 + math.floor(NickSession.roll(101) * #list) % #list]
end

-- The gap lives HERE rather than at each call site. Control gained three new
-- reasons to talk (patrol relays, the helicopter, witness calls) and a relay
-- that flickers across the 120m boundary would have had him narrating every
-- second of it. One voice, one throttle.
local function radio(list)
    if not list or #list == 0 then return end
    if GetGameTimer() < state.radioAt then return end

    setState({ radioAt = GetGameTimer() + Config.flavour.RADIO_GAP_S * 1000 })

    local line = list[math.random(#list)]:format(epithet())

    for _, src in ipairs(GetPlayers()) do
        local id = tonumber(src)
        if id and id ~= state.robber then
            TriggerClientEvent('nick:radio', id, line)
        end
    end
end

-- ===== whose turn it is =====
-- Everyone takes a turn as the robber; nobody goes twice on the bounce. The
-- memory lives on disk (server/session.lua) because PUSH LIVE restarts this
-- resource several times an evening and an in-memory rota is a coin toss
-- wearing a rota's clothes.
local function nextRobber(players)
    local roster = {}
    for _, src in ipairs(players) do
        local id = tonumber(src)
        if id then roster[#roster + 1] = { id = id, name = GetPlayerName(id) } end
    end

    if #roster == 0 then return nil end
    table.sort(roster, function(a, b) return a.id < b.id end)

    local previous = NickSession.lastRobber()
    local at = nil

    for index, player in ipairs(roster) do
        if player.name == previous then at = index break end
    end

    -- Nobody here went last (first round of the night, or they have left):
    -- draw at random rather than always opening with the lowest server id.
    local pick = at and roster[(at % #roster) + 1] or roster[math.random(#roster)]

    NickSession.rememberRobber(pick.name)
    return pick.id
end

-- ===== the map gate =====
-- Zero coordinates are tagged and a coordinate may never be guessed, so the
-- mode ships complete and refuses to deal until the tag board has caught up.
local function refuseUntagged(gaps)
    tell('Not yet - Nick of Time has no map. Nothing on this list is tagged:')

    for _, gap in ipairs(gaps) do
        tell(('  %s: %d tagged, need %d to play (%d for the real thing) - %s'):format(
            gap.label, gap.have, gap.min, gap.want, gap.tag))
    end

    tell('Tag them at https://sbm.dazrave.uk/tag under gametype "nick-of-time", then /nick start.')
end

-- ===== the round, as the framework sees it =====

-- Said once an evening, not once a round: the default-map disclaimer matters
-- the first time and is wallpaper by the third.
local defaultMapNoted = false

-- OnStart. The framework has already claimed the world, muted NPC heat, set
-- the dusk clock and dealt everyone onto 'police' by the time this runs.
local function onStart()
    local gaps = NickSession.missing()
    if #gaps > 0 then
        refuseUntagged(gaps)
        return exports.core:EndGametype('untagged')
    end

    local players = GetPlayers()
    if #players < Config.round.MIN_PLAYERS then
        tell(('Need %d in the server: one robber and someone to chase him.'):format(
            Config.round.MIN_PLAYERS))
        return exports.core:EndGametype('short-handed')
    end

    -- The map under everyone's wheels is the made-up default set (config.lua,
    -- Darren's game-night order). Say so, so the first door that turns out to
    -- be a hedge gets reported to the tag board rather than litigated in chat.
    if Config.locations.DEFAULT_MAP and not defaultMapNoted then
        defaultMapNoted = true
        tell('Tonight\'s map is the made-up default set (Darren\'s orders). If a shop turns out to be a wall, tag the real one at https://sbm.dazrave.uk/tag.')
    end

    local robber = nextRobber(players)
    local now    = GetGameTimer()

    NickDetect.reset()
    NickHeist.begin()
    NickEscalation.reset()

    -- The rota's pick moves over by hand - the 'robber' team is assign=false,
    -- so the framework's deal never touches it. Cross-team friendly fire then
    -- gives exactly the round we want: tyres pop, the robber takes hits, and
    -- the law cannot wing each other.
    exports.core:SetTeam(robber, 'robber')

    -- Seeded once per session and reused identically every round: the scope's
    -- fairness requirement is that nobody's turn gets an easier city.
    local robberSpawn = NickSession.pick(Config.locations.robberSpawns, 1, 7)[1]
    local copSpawn    = NickSession.pick(Config.locations.copSpawns, 1, 13)[1]

    -- A fresh table, NOT setState: a key written as nil in a constructor is
    -- simply absent, so a merge would quietly keep last round's values.
    state = {
        phase       = 'setup',
        robber      = robber,
        robberName  = GetPlayerName(robber),
        startsAt    = now + Config.round.READY_S * 1000,
        endsAt      = now + (Config.round.READY_S + Config.round.ROUND_LENGTH_S) * 1000,
        lastTick    = now,
        pos         = nil,
        copSpawn    = copSpawn,
        lastContact = 'cold',
        radioAt     = 0,
        heliOffered = false,
        lastStars   = 0,
    }

    local firstCop = nil
    for _, src in ipairs(players) do
        local id = tonumber(src)
        if id ~= robber and not firstCop then firstCop = id end
    end

    local map = NickHeist.map()

    CreateThread(function()
        Wait(1500) -- let the teams land before anyone gets moved

        for _, src in ipairs(players) do
            local id       = tonumber(src)
            local isRobber = (id == robber)

            TriggerClientEvent('nick:role', id, {
                isRobber   = isRobber,
                robberId   = robber,
                robberName = state.robberName,
                spawn      = isRobber and robberSpawn or copSpawn,
                spawnFleet = (id == firstCop), -- exactly one client spawns the cars
            })

            -- The police get the shops (guessing which one he hits next is
            -- half their job) and nothing else. The safehouses are the
            -- robber's business until he uses one.
            TriggerClientEvent('nick:map', id, {
                sites  = map.sites,
                houses = isRobber and map.houses or nil,
            })
        end
    end)

    tell(('%s is on the rob. Ten minutes. Everyone else is the law.'):format(state.robberName))
    tell('Only what he gets through a safehouse door counts. Everything in the bag when you nick him is gone.')
end

-- The events heist.lua queued up, turned into things people can see.
local function announce(events)
    for _, event in ipairs(events) do
        if event.kind == 'alarm' then
            TriggerClientEvent('nick:ping', -1, 'alarm', event, ('Alarm - %s'):format(event.name or 'a shop'))
            tell(('999: alarm going off at %s.'):format(event.name or 'a shop'))

        elseif event.kind == 'stash' then
            -- Banking is loud. The safehouse he just used is on their map now,
            -- which is the price of turning a bag into a score.
            TriggerClientEvent('nick:ping', -1, 'stash', event, ('Stash spotted - %s'):format(event.name or 'a doorway'))
            tell('Word is he just dropped a bag off somewhere. That door is burned.')

        elseif event.kind == 'exit' and event.reason == 'empty' and state.robber then
            TriggerClientEvent('nick:purseNote', state.robber, ('%s is cleaned out.'):format(event.name or 'The shop'))

        elseif event.kind == 'car' then
            -- The paperwork, read like a logbook entry. Lines live in config
            -- with the rest of the retelling; the fallback is only for a
            -- config stripped bare.
            local lines = Config.flavour.CAR_LINES
            local line  = (lines and #lines > 0) and lines[math.random(#lines)]
                or 'He cashed a %s in somewhere. That is £%s of somebody else\'s car.'
            tell(line:format(event.model or 'car', event.value or 0))

        -- ===== escalation =====
        elseif event.kind == 'relay' then
            -- A patrol has him. Said on the radio rather than shown as a
            -- different kind of dot, because the map treats every source the
            -- same (pillar 1) and only the FEELING should differ.
            radio(Config.flavour.RADIO_RELAY)

        elseif event.kind == 'witness' then
            TriggerClientEvent('nick:ping', -1, 'witness', event,
                event.saw == 'swap' and 'Witness - changed cars here'
                or event.saw == 'gunfire' and 'Witness - shots fired here'
                or 'Witness - collision here')
            radio(Config.flavour.RADIO_WITNESS)

        elseif event.kind == 'airunit' then
            -- The approval is public - a helicopter is not a secret for long,
            -- and the robber hearing it is half of what he pays star money
            -- for. WHERE she lands is not announced: that is a copper's
            -- position, and the robber gets his warning from the proximity
            -- icon when she is actually overhead, not from the tannoy.
            tell('Air unit approved. Somebody up there has a helicopter and a licence to match.')

        elseif event.kind == 'heli' then
            radio(Config.flavour.RADIO_HELI_UP)
            tell('Air support called in. Twenty seconds of truth, and it is not coming back.')

            -- The cosmetic helicopter is spawned by the robber's own client:
            -- it is the machine that owns the airspace he is in, the same
            -- reason chase spawns its units there. The PING does not depend on
            -- it existing - the favour is information, the aircraft is theatre.
            if state.robber then
                TriggerClientEvent('nick:heliUp', state.robber)
                TriggerClientEvent('nick:heliOverhead', state.robber)
            end
        end
    end
end

-- OnTick, ~1Hz from the framework while the round is live.
local function onTick()
    if state.phase == 'idle' then return end

    local now = GetGameTimer()
    local dt  = math.max(0.1, (now - state.lastTick) / 1000.0)
    setState({ lastTick = now })

    if state.phase == 'setup' and now >= state.startsAt then
        setState({ phase = 'active' })
        TriggerClientEvent('nick:go', -1)
        tell('He is out there. Find him.')
    end

    -- His position, read by the server itself once a second. If the ped is
    -- momentarily unreadable the merge keeps the last good fix.
    setState({ pos = robberPos() })

    -- Vanished means vanished. While he is in the safehouse bucket nothing is
    -- on anyone's street to be seen, so a patrol parked by the doorway must
    -- not keep a hard lock pinned on it - or even a relay line on the radio -
    -- because that would burn the safehouse before the stash does, and
    -- reveal-on-use is the stash's price, not the patrol's gift. Escalation
    -- simply gets no position while he is off the street.
    local hidden = state.robber and (GetPlayerRoutingBucket(state.robber) or 0) ~= 0

    -- Patrol positions, the contact score, the helicopter's own clock and the
    -- 999 calls that have finished ringing.
    NickEscalation.tick(dt, not hidden and state.pos or nil, NickDetect.contact(), state.robber)

    -- ONE DETECTION RULE (pillar 1). The bonus helicopter's ping and a patrol
    -- car's proximity relay do not get a private line to the map: they produce
    -- SIGHTINGS, exactly like a copper's eyeballs, so when the helicopter goes
    -- home or the patrol falls behind the picture decays through the same
    -- drifting circle instead of switching off. The air ping wins where both
    -- are live, because it is the one that ignores cover.
    if state.pos and not hidden then
        if NickEscalation.pinging() then
            NickDetect.sighting(state.pos, 'air')
        elseif NickEscalation.relaying() then
            NickDetect.sighting(state.pos, 'patrol')
        end
    end

    -- The guess moves on whether anyone is looking or not. This is the whole
    -- mode: doubling back behind a building sends the circle the wrong way.
    NickDetect.tick(dt)
    NickHeist.tick(state.pos, dt)
    announce(NickHeist.drain())
    announce(NickEscalation.drain())

    local remaining = math.max(0, math.ceil((state.endsAt - now) / 1000))
    local leader    = NickSession.leader()
    local mine      = state.robberName and NickSession.totalFor(state.robberName) or 0

    local stars  = NickHeist.stars()
    local status = NickDetect.publish()

    status.phase       = state.phase
    status.remaining   = remaining
    status.robberId    = state.robber
    status.robberName  = state.robberName
    status.publicTaken = NickHeist.publicTaken()
    status.stars       = stars
    status.emptySites  = NickHeist.publicEmpty()
    status.burned      = NickHeist.revealedHouses()

    local escalation = NickEscalation.publish(stars)
    status.patrolTarget = escalation.patrolTarget
    status.relay        = escalation.relay
    status.heliActive   = escalation.heliActive

    -- Control's commentary, one line per change of heart and never more often
    -- than RADIO_GAP_S. Only the changes worth a line: losing him, giving up
    -- on him, and getting him back after genuinely losing him - a lock
    -- regained within a few seconds is routine and control stays quiet.
    local was = state.lastContact
    if status.contact ~= was then
        setState({ lastContact = status.contact })

        local F = Config.flavour
        local lines

        if status.contact == 'soft' and was == 'hard' then
            lines = F.RADIO_LOST
        elseif status.contact == 'cold' and was == 'soft' then
            lines = F.RADIO_COLD
        elseif status.contact == 'hard' and was == 'cold' then
            lines = F.RADIO_FOUND
        end

        if lines then radio(lines) end -- radio() owns the throttle
    end

    -- The star-up sting. Every star is one he chose to earn by banking
    -- (pillar 4), so control gets to be pointed about it - once per star,
    -- through the same throttle as everything else control says.
    if stars > (state.lastStars or 0) then
        setState({ lastStars = stars })
        radio(Config.flavour.RADIO_STARS)
    end

    -- The number that makes a spectator sport of it. Everyone sees it, which
    -- is the point: the room knows how badly it is going before he does.
    if Config.round.SHOW_DELTA_TO_COPS and leader then
        status.leader = leader
        status.delta  = leader.total - (mine + NickHeist.stashed())
    end

    -- The robber's copy of the status has the entire detection picture
    -- stripped before it leaves the server. His stock client never drew any
    -- of it, but "where do the police THINK I am" broadcast to his machine
    -- was a wallhack waiting for a modded client to render it - and the
    -- pressure meter exists precisely so he gets a feeling, never the map.
    local robberStatus = {}
    for key, value in pairs(status) do robberStatus[key] = value end
    robberStatus.contact, robberStatus.via, robberStatus.track        = nil, nil, nil
    robberStatus.radius, robberStatus.heading, robberStatus.unseenFor = nil, nil, nil
    robberStatus.relay, robberStatus.heliActive                       = nil, nil

    -- The police-only channel. The lit helicopter button is deliberately NOT
    -- in the shared status: "their heli is available" is the same sentence as
    -- "they have completely lost you", and he is never told that in words.
    local forPolice = NickEscalation.policePublish()

    for _, src in ipairs(GetPlayers()) do
        local id = tonumber(src)

        if id == state.robber then
            TriggerClientEvent('nick:status', id, robberStatus)
        elseif id then
            TriggerClientEvent('nick:status', id, status)
            TriggerClientEvent('nick:police', id, forPolice)
        end
    end

    -- His own numbers go to him and to nobody else: a carried total on a
    -- police HUD would be a live position update in disguise.
    if state.robber then
        TriggerClientEvent('nick:purse', state.robber, NickHeist.purse(robberVehicle()))
    end

    -- Control offers the favour once, when it first becomes available.
    if forPolice.heliReady and not state.heliOffered then
        setState({ heliOffered = true })
        radio(Config.flavour.RADIO_HELI_READY)
    end

    if remaining <= 0 then exports.core:EndGametype('time') end
end

-- Everybody back into the world everyone else is in. A player left behind in
-- the safehouse bucket would be invisible for the rest of the evening, which
-- is the single worst bug this mode could ship.
local function unvanishAll()
    for _, src in ipairs(GetPlayers()) do
        local id = tonumber(src)
        if id then SetPlayerRoutingBucket(id, 0) end
    end
end

-- OnEnd. Every road out of a round comes through here, whatever ended it.
local function onEnd(reason)
    -- The two non-rounds, handled before anything else: onStart refused before
    -- a round existed, so there is no state to tear down. Take the world claim
    -- back immediately rather than leaving infected and pint stopped for the
    -- framework's eight second end-card grace over a round that never was.
    if reason == 'untagged' or reason == 'short-handed' then
        exports.core:releaseWorld()
        return 'hold'
    end

    if state.phase == 'idle' then return end

    -- The framework's own reasons translated into this mode's endings. Its
    -- round cap trails ours by a few seconds (onTick calls time first).
    local FRAMEWORK_REASONS = { time = 'time', stopped = 'abandoned' }
    local result = FRAMEWORK_REASONS[reason] or reason

    local stashed = NickHeist.stashed()
    local name    = state.robberName

    setState({ phase = 'idle' })
    unvanishAll()

    -- Half of the dual cleanup (plan §6, acceptance test 8): the clients bin
    -- their own patrols and helicopter, and the server bins everything it was
    -- told about regardless - so a client that crashed, left, or simply never
    -- heard the round end cannot leak a single entity into the next one.
    NickEscalation.sweep()

    -- Torn down by force (this resource or core going down): no drama, just
    -- make sure the next registration starts from idle.
    if reason == 'resource-stopped' or reason == 'core-stopped' then return end

    if name then NickSession.record(name, stashed) end

    TriggerClientEvent('nick:end', -1, result, name, stashed)

    local lines = {
        arrested   = ('%s got nicked. Everything in the bag goes back on the shelf. Banked: £%s.'):format(name or '?', stashed),
        ['called-it'] = ('%s called it a day and walked away with £%s.'):format(name or '?', stashed),
        time       = ('Ten minutes gone. %s banked £%s and is still holding whatever he never stashed - which is now nobody\'s.'):format(name or '?', stashed),
        fled       = ('%s left the server mid-job. The perfect crime, technically.'):format(name or '?'),
        abandoned  = 'Round abandoned.',
    }
    tell(lines[result] or 'Round over.')

    -- The retelling: the write-off, and a superlative where one was earned.
    -- Only for rounds that actually played out - a fled or abandoned round
    -- gets no paperwork.
    if result == 'arrested' or result == 'called-it' or result == 'time' then
        local F      = Config.flavour
        local taken  = NickHeist.taken()
        local heist  = NickHeist.review()
        local search = NickDetect.review()

        if taken > 0 and #F.STOCK_ITEMS > 0 then
            tell(('Insurance reckon £%s of stock, mostly %s.'):format(
                taken, F.STOCK_ITEMS[math.random(#F.STOCK_ITEMS)]))
        end

        if not search.everSeen then
            tell(F.NEVER_SEEN_LINE)
        elseif search.longestUnseenS >= F.GHOST_MIN_S then
            tell((F.GHOST_LINE):format(
                math.floor(search.longestUnseenS / 60), search.longestUnseenS % 60))
        end

        if heist.pettiest then
            local petty = heist.pettiest.method == 'smash' and F.PETTY_SMASH_LINE or F.PETTY_QUIET_LINE
            tell(petty:format(heist.pettiest.name, heist.pettiest.take))
        end
    end

    local leader = NickSession.leader()
    if leader then
        tell(('Session leader: %s on £%s.'):format(leader.name, leader.total))
    end
end

-- ===== the round, as the rest of this resource sees it =====
-- server/orders.lua handles everything the clients send, and every one of
-- those handlers needs to know the phase, who the robber is and where he
-- actually is. They get accessors rather than the state itself: exactly one
-- file owns the phase, and it is the one running the clock.
NickRound = {
    phase     = function() return state.phase end,
    robber    = function() return state.robber end,
    pos       = robberPos,
    vehicle   = robberVehicle,

    -- His ped, already checked for existence - every handler that measures
    -- anything wants the same three lines of guard.
    robberPed = function()
        if not state.robber then return nil end

        local ped = GetPlayerPed(state.robber)
        if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end

        return ped
    end,
}

exports('getState', function()
    return {
        phase   = state.phase,
        robber  = state.robberName,
        contact = NickDetect.contact(),
        stashed = NickHeist.stashed(),
    }
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    unvanishAll()
    NickEscalation.sweep() -- nothing this mode spawned outlives this mode
end)

-- ===== the declaration =====
-- Registered on every start of this resource AND of core: a core reboot wipes
-- the framework's registry, and a mode that doesn't put its hand back up
-- stops existing as far as /nick is concerned.
local function register()
    if state.phase ~= 'idle' then
        setState({ phase = 'idle' })
        unvanishAll()
        NickEscalation.sweep()
        tell('Core rebooted mid-round - round abandoned. /nick start to go again.')
    end

    exports.core:RegisterGametype('nick', {
        label = 'Nick of Time',

        -- Everyone is dealt onto 'police'; onStart moves the rota's pick to
        -- 'robber' by hand. No team loadouts here - client/police.lua issues
        -- the kit, so the robber never gets one by accident.
        teams = {
            { id = 'police', label = 'The Law' },
            { id = 'robber', label = 'The Robber', assign = false },
        },

        population   = 'alive',  -- a living city to hide in, nick cars out of, and be SEEN by

        -- 'custom': core's NPC heat stays muted (the stock police would
        -- arrest, shoot and end rounds - all three forbidden) and this mode
        -- brings its own law instead. Ours cannot do any of those things.
        police       = 'custom',
        friendlyFire = 'auto',   -- cross-team only: tyres pop, coppers can't wing each other

        clock = Config.round.CLOCK,

        -- Backstop only: onTick calls time on its own clock, which starts
        -- when everyone has actually been placed. This cap exists so a wedged
        -- round can never run forever.
        roundSeconds = Config.round.READY_S + Config.round.ROUND_LENGTH_S + 15,

        -- 0, not two, on purpose. The framework's floor would refuse before
        -- the map gate could speak, and "here is what to tag" is an answer you
        -- want from an empty console on a Tuesday, not from a full lobby on a
        -- Thursday. onStart enforces Config.round.MIN_PLAYERS itself.
        minPlayers = 0,

        -- Respawn is role-dependent (a copper gets up where they fell, the
        -- robber's round ends by arrest or by clock), so client/police.lua
        -- sets the policy per role rather than declaring one here.
        hooks = {
            OnStart = onStart,
            OnTick  = onTick,
            OnEnd   = onEnd,

            -- Late to the shift: the framework has already dealt them onto
            -- 'police'; this hands them the muster point, the shop map and -
            -- once the fade and the model swap have finished - the kit. No
            -- cruiser is held back for them, which is what the relief car
            -- thread is for.
            OnPlayerJoin = function(src)
                if state.phase == 'idle' then return end

                TriggerClientEvent('nick:role', src, {
                    isRobber   = false,
                    robberId   = state.robber,
                    robberName = state.robberName,
                    spawn      = state.copSpawn,
                    spawnFleet = false,
                })
                TriggerClientEvent('nick:map', src, { sites = NickHeist.map().sites })

                CreateThread(function()
                    Wait(4000) -- the fade, the teleport and the model swap first
                    if state.phase == 'active' and GetPlayerName(src) then
                        TriggerClientEvent('nick:go', src)
                    end
                end)
            end,

            OnPlayerLeave = function(src)
                if state.phase ~= 'idle' and src == state.robber then
                    exports.core:EndGametype('fled')
                end
            end,
        },
    })
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() or resource == 'core' then
        register()
    end
end)
