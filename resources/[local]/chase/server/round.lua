-- Round director. The server owns the phase, the fugitive's identity and the
-- sighting state; clients own eyes, blips and wheels.
--
-- The world plumbing is the gametype framework's job now (core/server/
-- gametype.lua): claiming the city, muting NPC heat, the golden-hour clock,
-- friendly fire and the /chase command itself all come off the descriptor at
-- the bottom of this file. What stays here is the drama - the rota, the head
-- start, sightings, and how a round ends.
local state = {
    phase          = 'idle', -- idle | headstart | active
    fugitive       = nil,    -- server id
    fugitiveName   = nil,
    headstartEndsAt = 0,
    endsAt         = 0,
    lastSeen       = nil,    -- vector3-ish table
    lastSeenAt     = 0,
    lastHeading    = nil,    -- degrees, the way they were going when last seen
    fugitivePos    = nil,    -- heartbeat, used only for the final alert
}

-- Air support announces itself once a round, when the helicopter is actually
-- up. Kept out of `state` on purpose: it is a fact about the chat log, not
-- about the round, and the fugitive's client is what decides when it's true.
local airborneAnnounced = false

local function setState(next)
    local merged = {}
    for key, value in pairs(state) do merged[key] = value end
    for key, value in pairs(next) do merged[key] = value end
    state = merged
end

local function tell(message)
    TriggerClientEvent('chat:addMessage', -1, {
        color = { 66, 150, 245 },
        args  = { 'chase', message },
    })
end

-- The two endings that leave a body. Every other ending is tidy by its nature:
-- an arrest happens with the police stood over the suspect, an escape happens
-- on the whistle. A death happens wherever it happened - the suspect face down
-- at the bottom of a ravine, the fleet abandoned across half the map, everyone
-- else scattered and miles apart - and free roam simply inherited all of it,
-- with the fugitive left on the floor waiting on a backstop to peel them up.
local ENDS_IN_A_BODY = { shot = true, crashed = true }

-- ===== whose turn it is =====
-- Everyone gets a go, in order, and nobody does it twice on the bounce.
--
-- Two things were quietly wiping this memory, and both are routine (#51).
--
-- The first: this whole block used to sit INSIDE start(), so `lastFugitive`
-- was a fresh local on every single round. It was nil every time the rota came
-- to read it, which meant the "first suspect of the night is random" branch was
-- the only branch that ever ran. The rota was a coin toss wearing a rota's
-- clothes, and somebody could absolutely go twice on the bounce.
--
-- The second: PUSH LIVE restarts this resource several times an evening, which
-- takes any in-memory answer with it. So it is written to disk. It is kept by
-- NAME rather than by server id, because ids are handed out fresh on every
-- reconnect and would not survive either.
local ROTA_FILE = '.last-fugitive'

local function rememberFugitive(name)
    if not name or name == '' then return end
    SaveResourceFile(GetCurrentResourceName(), ROTA_FILE, name, -1)
end

local function whoWentLast()
    local stored = LoadResourceFile(GetCurrentResourceName(), ROTA_FILE)
    if not stored or stored == '' then return nil end
    return stored
end

local function nextFugitive(players)
    local roster = {}
    for _, src in ipairs(players) do
        local id = tonumber(src)
        if id then roster[#roster + 1] = { id = id, name = GetPlayerName(id) } end
    end

    if #roster == 0 then return nil end

    -- Sorted so the order is the same every round rather than following
    -- whatever order GetPlayers happened to return.
    table.sort(roster, function(a, b) return a.id < b.id end)

    local previous = whoWentLast()
    local at = nil

    for index, player in ipairs(roster) do
        if player.name == previous then at = index break end
    end

    -- Nobody here went last: first round of the night, or they have since left.
    -- Draw at random so the rota doesn't always open with whoever happens to
    -- hold the lowest server id. Otherwise it is strictly the next one along,
    -- which is what makes going twice in a row impossible rather than unlikely.
    local pick = at and roster[(at % #roster) + 1] or roster[math.random(#roster)]

    rememberFugitive(pick.name)
    return pick.id
end

-- ===== square one, then straight back out again =====
-- resetWorld() is telemetry's own half of /resetgame: it bins the leftover
-- cars and wrecks and puts everybody back on their feet together in one
-- place, the body included. Then the mode goes again, which is what a death
-- ought to mean - another go, not an evening spent driving back from wherever
-- the round died.
local function resetAndGoAgain()
    Wait(6000) -- let the end-of-round shard finish playing first
    if state.phase ~= 'idle' then return end

    tell('Putting everything back where it belongs. Then we go again.')
    pcall(function() exports.telemetry:resetWorld() end)

    Wait(7000) -- it fades everyone out, gathers them up and fades back in

    -- Somebody may have started a round by hand in the gap, and people do
    -- leave. We asked the framework to HOLD the world claim (see onEnd)
    -- precisely so this stretch didn't bounce the default stack up and down,
    -- which means letting go is on us if the rematch is off.
    if state.phase ~= 'idle' then return end
    if #GetPlayers() < 2 then return exports.core:releaseWorld() end

    ExecuteCommand('chase start') -- the framework owns the command now
end

-- ===== the round, as the framework sees it =====

-- OnStart. The framework has already claimed the world, muted NPC heat, set
-- the golden hour and dealt everyone onto 'police' by the time this runs.
local function onStart()
    local players  = GetPlayers()
    local fugitive = nextFugitive(players)
    local now      = GetGameTimer()

    airborneAnnounced = false

    -- The rota's pick moves over by hand (the 'fugitive' team is assign =
    -- false, so the deal never touches it). Cross-team friendly fire ('auto')
    -- then gives exactly the old round minus cop-on-cop shooting: tyres pop,
    -- the fugitive takes hits, and the law can no longer wing each other.
    exports.core:SetTeam(fugitive, 'fugitive')

    -- A fresh table, NOT setState. setState merges with pairs(), and a key
    -- written as nil in a table constructor is simply absent - pairs() never
    -- sees it, so `lastSeen = nil` through the merge KEPT last round's final
    -- sighting. Combined with lastSeenAt going back to 0, the shake-off clock
    -- then read "spotted hours ago" the moment round two went active and ended
    -- it on the spot - one good game, then every round after it instantly
    -- called as a getaway (#52). A new round is a new state, not a patch on
    -- the old one.
    state = {
        phase           = 'headstart',
        fugitive        = fugitive,
        fugitiveName    = GetPlayerName(fugitive),
        -- Provisional. The real countdown is started further down, once
        -- everybody has actually been placed - roles go out 1.5s from here and
        -- a client can spend another 2.5s waiting for collision, so counting
        -- from this moment had the countdown most of the way through before
        -- anyone could see it. Seeded long so nothing releases early if the
        -- setup below ever fails.
        headstartEndsAt = now + 60000,
        endsAt          = now + (Config.readySeconds + Config.headstartSeconds + Config.roundSeconds) * 1000,
        lastSeen        = nil,
        lastSeenAt      = 0,
        lastHeading     = nil,
        fugitivePos     = nil,
    }

    local spawnIndex   = math.random(#Config.fugitive.spawns)
    local stationIndex = math.random(#Config.stations)
    local firstCop   = nil

    for _, src in ipairs(players) do
        local id = tonumber(src)
        if id ~= fugitive and not firstCop then firstCop = id end
    end

    -- Clear the yard first and give it a moment to actually happen, otherwise
    -- the new fleet spawns into last round's wreckage.
    TriggerClientEvent('chase:clearArea', -1, stationIndex)

    CreateThread(function()
        Wait(1500)

        for _, src in ipairs(players) do
            local id = tonumber(src)
            TriggerClientEvent('chase:role', id, {
                isFugitive   = (id == fugitive),
                fugitiveId   = fugitive,
                fugitiveName = state.fugitiveName,
                spawnIndex   = spawnIndex,
                stationIndex = stationIndex,
                spawnFleet   = (id == firstCop), -- exactly one client spawns the cars
            })
        end

        -- Everyone has their role and has had time to be stood up. NOW start
        -- counting, so the number on screen is the whole head start rather
        -- than whatever was left of it by the time the world loaded.
        Wait(Config.readySeconds * 1000)

        if state.phase == 'headstart' then
            local from = GetGameTimer()
            setState({
                headstartEndsAt = from + Config.headstartSeconds * 1000,
                endsAt          = from + (Config.headstartSeconds + Config.roundSeconds) * 1000,
            })
        end
    end)

    -- With no hold there is nothing to count down, and "0s head start" reads
    -- like something broke.
    if Config.headstartSeconds > 0 then
        tell(('%s is the fugitive - stood right there. %ds head start and you can watch them go.'):format(
            state.fugitiveName, Config.headstartSeconds))
    else
        tell(('%s is the fugitive - stood right there. GO.'):format(state.fugitiveName))
    end
    tell('You CANNOT shoot them dead - shoot the tyres, corner them, drag them out, nick them.')

    if Config.shakeOff.enabled then
        tell(('Once they have been spotted, %d seconds with nobody laying eyes on them and they have won.'):format(
            Config.shakeOff.seconds))
    end
end

-- OnTick, ~1Hz from the framework while the round is live: release the
-- hounds, broadcast status, call time.
local function onTick()
    if state.phase == 'idle' then return end

    local now = GetGameTimer()

    if state.phase == 'headstart' and now >= state.headstartEndsAt then
        setState({ phase = 'active' })
        TriggerClientEvent('chase:release', -1)
        tell('Units released. Go get them.')
    end

    local remaining  = math.max(0, math.ceil((state.endsAt - now) / 1000))
    local finalAlert = state.phase == 'active' and remaining <= Config.finalAlertSeconds
    local tracking   = state.lastSeen ~= nil and (now - state.lastSeenAt) < Config.sight.holdMs

    -- During the head start the suspect is in plain sight: everyone
    -- watches which way they went, then the leash comes off.
    local headstart = state.phase == 'headstart'

    -- The shake-off clock. Runs only once they have actually been
    -- spotted, and stops dead during the citywide alert - the whole
    -- city has a live trace by then, so "nobody has seen me" would be
    -- a lie the scoreboard shouldn't reward.
    local shakeIn = nil

    -- lastSeenAt > 0 as well as lastSeen: the pair must be from THIS
    -- round. Belt and braces against any future path that leaves one
    -- half stale - a zero timestamp read as "spotted at server boot"
    -- is exactly what was ending rounds at the whistle.
    if Config.shakeOff.enabled and state.phase == 'active'
        and state.lastSeen and state.lastSeenAt > 0 and not finalAlert then
        shakeIn = math.max(0, math.ceil(
            (Config.shakeOff.seconds * 1000 - (now - state.lastSeenAt)) / 1000))
    end

    TriggerClientEvent('chase:status', -1, {
        phase        = state.phase,
        remaining    = remaining,
        headstart    = math.max(0, math.ceil((state.headstartEndsAt - now) / 1000)),
        fugitiveId   = state.fugitive,
        fugitiveName = state.fugitiveName,
        -- The suspect is always on the map now. Losing line of sight
        -- no longer freezes the dot at a last-known position; it just
        -- means the ping the police get is a stale one, and how stale
        -- is decided client-side by how far away they are.
        --
        -- `tracking` still means "eyes on" - the client uses it for
        -- the ring and the flashing - so the difference between a live
        -- lock and a cold trace is still visible at a glance.
        tracking     = tracking or finalAlert or headstart,
        trackPos     = state.fugitivePos or state.lastSeen,
        lastKnown    = state.lastSeen,
        lastHeading  = state.lastHeading,
        unseenFor    = state.lastSeen and math.floor((now - state.lastSeenAt) / 1000) or nil,
        finalAlert   = finalAlert,
        shakeIn      = shakeIn,
    })

    -- Losing them outright ends it before the clock does.
    if shakeIn == 0 then
        exports.core:EndGametype('shaken')
    elseif remaining <= 0 then
        exports.core:EndGametype('escaped')
    end
end

-- OnEnd. Every road out of a round comes through here, whatever ended it:
-- our own win conditions (the EndGametype calls dotted about), /chase stop,
-- the framework's backstop clock, or the resource being stopped under us.
local function onEnd(reason)
    if state.phase == 'idle' then return end

    -- The framework's own reasons, translated into this mode's endings. Its
    -- round cap trails ours by a few seconds (onTick calls time first), so
    -- 'time' still means the fugitive outlasted the clock; 'stopped' keeps
    -- the old /chase stop behaviour of scoring it as a getaway.
    local FRAMEWORK_REASONS = { time = 'escaped', stopped = 'escaped' }
    local result = FRAMEWORK_REASONS[reason] or reason

    setState({ phase = 'idle' })

    -- Torn down by force (this resource or core going down): no drama, just
    -- make sure the next registration starts from idle.
    if reason == 'resource-stopped' or reason == 'core-stopped' then return end

    TriggerClientEvent('chase:end', -1, result, state.fugitiveName)

    local lines = {
        escaped  = ('%s got clean away. Drinks on the police budget.'):format(state.fugitiveName or '?'),
        shaken   = ('%s shook the tail. A full minute, no eyes, no lock, no ping. Textbook.'):format(state.fugitiveName or '?'),
        arrested = ('%s got nicked. By the book.'):format(state.fugitiveName or '?'),
        shot     = 'You SHOT them. The chief is furious. Tyres, people. TYRES.',
        crashed  = 'The suspect and their bike parted company permanently. Case closes itself.',
        fled     = 'The fugitive left the server. Ultimate escape, technically.',
    }
    tell(lines[result] or 'Round over.')
    if reason == 'stopped' then tell('Round abandoned.') end

    if ENDS_IN_A_BODY[result] then
        CreateThread(resetAndGoAgain)
        -- Hold the world claim: the reset is about to sweep the map and go
        -- again, and a release here would bounce infected and pint up for
        -- five seconds in between. resetAndGoAgain lets go if the rematch
        -- is off.
        return 'hold'
    end
end

-- ===== eyes, reports, endings =====

-- Somebody has eyes on the suspect. Shared by the coppers on the ground and by
-- the helicopter, because a sighting is a sighting: it refreshes the lock and
-- it sets the direction of travel.
local function recordSighting(coords)
    -- Which way they were travelling between the last two sightings. Once the
    -- trail goes cold this is all the police get, and it is the difference
    -- between searching a circle and searching the right half of one.
    local heading = state.lastHeading

    if state.lastSeen then
        local dx, dy = coords.x - state.lastSeen.x, coords.y - state.lastSeen.y
        if (dx * dx + dy * dy) > 4.0 then   -- ignore standing still
            heading = math.deg(math.atan(dx, -dy)) % 360.0
        end
    end

    setState({ lastSeen = coords, lastSeenAt = GetGameTimer(), lastHeading = heading })
end

-- A cop laid eyes on the fugitive.
RegisterNetEvent('chase:see', function(coords)
    local source = source
    if state.phase ~= 'active' or source == state.fugitive then return end

    recordSighting(coords)
end)

-- The helicopter has them. This is the exact opposite check to `chase:see`:
-- air support is an NPC flown by the suspect's own client (see client/heli.lua
-- for why), so the ONLY machine allowed to report it is the one `chase:see`
-- refuses to listen to.
--
-- Trusting the fugitive's client with this costs nothing. It gains them
-- nothing to lie in either direction, and the client already reports its own
-- position every second through `chase:heartbeat` regardless.
RegisterNetEvent('chase:airEyes', function(coords)
    local source = source
    if state.phase ~= 'active' or source ~= state.fugitive then return end

    recordSighting(coords)
end)

-- Air support is up. Said once, and only when the helicopter genuinely exists,
-- so the line is never a promise the round doesn't keep.
RegisterNetEvent('chase:airborne', function()
    local source = source
    if state.phase ~= 'active' or source ~= state.fugitive then return end
    if airborneAnnounced then return end

    airborneAnnounced = true
    tell('Air support is up. That helicopter is why the suspect keeps showing on your map.')
    tell('Get under something and the lock goes cold - bridges, tunnels, the multi-storeys.')
end)

-- Fugitive position heartbeat; only ever shown during the final alert.
RegisterNetEvent('chase:heartbeat', function(coords)
    local source = source
    if source ~= state.fugitive then return end
    setState({ fugitivePos = coords })
end)

-- Breadcrumbs: stolen-car and witness reports, delivered late like a real
-- 999 call.
RegisterNetEvent('chase:report', function(kind, coords, label)
    local source = source
    if source ~= state.fugitive or state.phase ~= 'active' then return end

    local delay = kind == 'stolen' and Config.reports.stolenDelayMs or Config.reports.witnessDelayMs

    CreateThread(function()
        Wait(delay)
        if state.phase ~= 'active' then return end

        TriggerClientEvent('chase:ping', -1, kind, coords, label)
        tell(kind == 'stolen'
            and ('999 call: %s just got taken.'):format(label or 'a vehicle')
            or  ('999 call: reports of a collision, %s.'):format(label or 'somewhere'))
    end)
end)

RegisterNetEvent('chase:arrest', function()
    local source = source
    if state.phase ~= 'active' or source == state.fugitive then return end
    TriggerEvent('core:stat', source, 'arrests', 1) -- season scoreboard
    exports.core:EndGametype('arrested')
end)

-- Gunfire can no longer finish the suspect, so a death here is the suspect's
-- own driving. The 'shot' ending is kept for the day someone finds a way.
RegisterNetEvent('chase:died', function(byCop)
    local source = source
    if source ~= state.fugitive or state.phase == 'idle' then return end
    exports.core:EndGametype(byCop and 'shot' or 'crashed')
end)

exports('getState', function()
    local tracking = state.lastSeen ~= nil
        and (GetGameTimer() - state.lastSeenAt) < Config.sight.holdMs

    return {
        phase    = state.phase,
        fugitive = state.fugitiveName,
        tracking = tracking and true or false,
    }
end)

-- ===== the declaration =====
-- Registered on every start of this resource AND of core: a core reboot
-- wipes the framework's registry, and a mode that doesn't put its hand back
-- up stops existing as far as /chase is concerned.
local function register()
    -- A core reboot mid-round also takes the framework's round state with
    -- it, so nothing is ticking this one any more. Say so rather than sit
    -- there believing a dead round is live.
    if state.phase ~= 'idle' then
        setState({ phase = 'idle' })
        tell('Core rebooted mid-round - round abandoned. /chase start to go again.')
    end

    exports.core:RegisterGametype('chase', {
        label = 'Scrap Run',

        -- Everyone is dealt onto 'police'; onStart moves the rota's pick to
        -- 'fugitive' by hand (assign = false keeps the deal off that slot).
        -- No team loadouts on purpose: the cop kit is only issued on release
        -- (client/cop.lua), so nobody shoots from inside the head start.
        teams = {
            { id = 'police',   label = 'The Law' },
            { id = 'fugitive', label = 'The Fugitive', assign = false },
        },

        population   = 'alive',  -- a living city to hide in
        police       = 'custom', -- NPC heat muted; client/ai.lua brings its own law
        friendlyFire = 'auto',   -- cross-team only: tyres pop, coppers can't wing each other

        -- Golden-hour city for the whole round, put back afterwards.
        clock = { hour = 17, minute = 30, weather = 'EXTRASUNNY', freeze = true },

        -- Backstop only: onTick calls full time as 'escaped' on its own
        -- clock, which starts counting when everyone is actually placed.
        -- This cap exists so a wedged round can never run forever.
        roundSeconds = Config.readySeconds + Config.headstartSeconds + Config.roundSeconds + 15,

        minPlayers = 2, -- one rabbit, some hounds

        -- Respawn is deliberately NOT declared: it is role-dependent (cops
        -- get up where they fell, the fugitive's death ends the round), so
        -- client/cop.lua keeps setting the policy per role as it always has.
        hooks = {
            OnStart = onStart,
            OnTick  = onTick,
            OnEnd   = onEnd,
            OnPlayerLeave = function(src)
                if state.phase ~= 'idle' and src == state.fugitive then
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
