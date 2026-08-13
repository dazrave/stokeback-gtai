-- The race itself: who is in it, how far along they are, and who is allowed to
-- say so. The server owns every one of those answers.
--
-- A client's job is to notice it is stood in the ring and say "I claim number
-- 12". This file decides whether 12 is the next number that racer is entitled
-- to, whether he is actually there - read off the server's OWN copy of his ped,
-- never out of the event, because coordinates in a net event are the one thing
-- a modded client can lie about - and whether he is doing it in the right
-- thing. Running checkpoints do not count from a car, and the motocross leg is
-- not a jogging event.
--
-- A global rather than an export: round.lua lives in the same resource, and a
-- resource cannot call its own exports.
TriRace = {}

local racers  = {}  -- [src] = { name, slot, at, finished, position, ... }
local course  = nil
local finished = 0  -- how many have crossed the line, i.e. the next position

-- ===== reading the world, not the message =====

local function pedOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return ped
end

local function coordsOf(src)
    local ped = pedOf(src)
    if not ped then return nil end
    return GetEntityCoords(ped)
end

-- What they are sitting in, as far as the server can tell. Server-side entity
-- natives need OneSync (which this server runs) and can still come back empty
-- for a player who is mid-stream; `nil` therefore means "cannot tell" and is
-- treated as innocent everywhere below. A race that refuses a legitimate
-- checkpoint because the server blinked is worse than a race somebody could
-- theoretically cheat by unplugging their network cable.
local function vehicleOf(src)
    local ped = pedOf(src)
    if not ped then return nil end

    local ok, vehicle = pcall(GetVehiclePedIsIn, ped)
    if not ok then return nil end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 0 end

    return vehicle
end

local function distance(a, b)
    if not a or not b then return nil end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ===== the roster =====

function TriRace.begin(built, players)
    course, racers, finished = built, {}, 0

    local slot = 0
    for _, src in ipairs(players) do
        local id = tonumber(src)
        if id then
            slot = slot + 1
            TriRace.add(id, slot)
        end
    end
end

function TriRace.add(src, slot)
    if not course then return nil end

    local existing = racers[src]
    if existing then return existing end

    local count = 0
    for _ in pairs(racers) do count = count + 1 end

    racers[src] = {
        name      = GetPlayerName(src) or ('#' .. src),
        slot      = slot or (count + 1),
        at        = 1,      -- the waypoint they are heading for
        leg       = Config.LEG_ORDER[1],
        finished  = false,
        dnf       = false,
        position  = nil,
        startedAt = GetGameTimer(),
        finishedAt = nil,
        vehicleAt = 0,      -- last time they were handed a vehicle
        issued    = {},     -- [leg] = true once their line-up has been put out
    }

    return racers[src]
end

function TriRace.drop(src)
    racers[src] = nil
end

function TriRace.get(src)
    return racers[src]
end

function TriRace.course()
    return course
end

function TriRace.waypoint(index)
    if not course then return nil end
    return course.waypoints[index]
end

function TriRace.clear()
    course, racers, finished = nil, {}, 0
end

-- Everyone still on the course. The number the finish window cares about.
function TriRace.stillRacing()
    local count = 0
    for _, racer in pairs(racers) do
        if not racer.finished and not racer.dnf then count = count + 1 end
    end
    return count
end

function TriRace.anyFinished()
    return finished > 0
end

-- ===== claiming a checkpoint =====

-- Is this racer in the right thing to be claiming this waypoint? Strictness
-- is a config knob because the first time somebody's bike ends up in a canyon
-- and he walks the last checkpoint, the room will have opinions.
local function vehicleAllows(src, waypoint)
    local rule = waypoint.require or 'none'
    if rule == 'none' then return true end

    local vehicle = vehicleOf(src)
    if vehicle == nil then return true end -- cannot tell; do not punish

    if rule == 'foot' then
        if not Config.rules.FOOT_CHECK then return true end
        return vehicle == 0, 'on foot for the running leg'
    end

    -- rule == 'vehicle'
    local check = Config.rules.VEHICLE_CHECK
    if check == 'off' then return true end
    if vehicle == 0 then
        return false, ('in the %s for this leg'):format(waypoint.model or 'vehicle')
    end
    if check == 'any' then return true end

    local wanted = GetHashKey(waypoint.model or '')
    if GetEntityModel(vehicle) ~= wanted then
        return false, ('in the %s, not that'):format(waypoint.model or 'right vehicle')
    end

    return true
end

-- The one function a client's word gets anywhere near. Returns:
--   ok, event, waypoint    event = 'advanced' | 'leg' | 'finished'
--   false, reason
function TriRace.claim(src, index)
    local racer = racers[src]
    if not racer then return false, 'not racing' end
    if racer.finished or racer.dnf then return false, 'already done' end
    if not course then return false, 'no course' end

    -- In order, always: the only index anybody may claim is their own next
    -- one. Which makes a spammed or replayed claim harmless rather than
    -- something to rate limit.
    if index ~= racer.at then return false, 'out of order' end

    local waypoint = course.waypoints[index]
    if not waypoint then return false, 'no such checkpoint' end

    local gap = distance(coordsOf(src), waypoint.coords)
    if gap and gap > (waypoint.radius or 10.0) * (Config.rules.RADIUS_SLACK or 1.5) then
        return false, 'not actually there'
    end

    local allowed, want = vehicleAllows(src, waypoint)
    if not allowed then return false, want end

    racer.at = index + 1

    -- Off the end of the list: that was the finish.
    if racer.at > #course.waypoints then
        finished = finished + 1

        racer.finished   = true
        racer.position   = finished
        racer.finishedAt = GetGameTimer()

        return true, 'finished', waypoint
    end

    if waypoint.opens then
        racer.leg = waypoint.opens
        return true, 'leg', waypoint
    end

    racer.leg = course.waypoints[racer.at].leg
    return true, 'advanced', waypoint
end

-- ===== vehicles =====

-- A client asks for its bike or its plane; this decides whether it gets one.
-- Granted only to a racer who has actually reached a leg with vehicles in it,
-- and never more often than the cooldown - otherwise "I have written one off"
-- becomes a way to carpet a hillside in bikes.
--
-- `leg` is passed explicitly for the transition grant, which happens BEFORE
-- the racer gets there: the bikes are meant to be sat waiting as he comes over
-- the last rise, not to appear out of the air the moment he arrives.
function TriRace.grantVehicle(src, why, leg)
    local racer = racers[src]
    if not racer or racer.finished or racer.dnf then return nil end

    leg = leg or racer.leg

    local legCfg = Config.legs[leg]
    if not legCfg or legCfg.REQUIRE ~= 'vehicle' then return nil end

    local now = GetGameTimer()

    if why == 'transition' then
        -- Exactly one line-up per racer per leg, however many times the
        -- checkpoint either side of it gets re-claimed.
        if racer.issued[leg] then return nil end
        racer.issued[leg] = true
    elseif now - racer.vehicleAt < (Config.vehicles.RECOVER_COOLDOWN_S or 8) * 1000 then
        return nil
    end

    racer.vehicleAt = now

    return {
        leg   = leg,
        slot  = racer.slot,
        model = legCfg.MODEL,
        why   = why,
        -- Where to put it: laid out at the transition for a fresh start, or at
        -- the last waypoint he actually reached when he is recovering from a
        -- crash halfway down a hill.
        at    = racer.at,
    }
end

-- ===== the table =====

-- Who is where, in the order a scoreboard would put them. Finishers first by
-- when they finished, then everyone still going by how far along they are,
-- then - the scope's tie-break - by how close they are to the next checkpoint,
-- which is the difference between "joint fourth" and an actual race.
function TriRace.standings()
    local list = {}

    for src, racer in pairs(racers) do
        local waypoint = course and course.waypoints[racer.at] or nil
        local gap      = waypoint and distance(coordsOf(src), waypoint.coords) or nil

        list[#list + 1] = {
            src      = src,
            name     = racer.name,
            at       = racer.at,
            leg      = racer.leg,
            finished = racer.finished,
            dnf      = racer.dnf,
            position = racer.position,
            time     = racer.finishedAt and (racer.finishedAt - racer.startedAt) or nil,
            toNext   = gap,
            waypoint = waypoint,
        }
    end

    table.sort(list, function(a, b)
        if a.finished ~= b.finished then return a.finished end
        if a.finished and b.finished then return (a.position or 99) < (b.position or 99) end
        if a.dnf ~= b.dnf then return b.dnf end
        if a.at ~= b.at then return a.at > b.at end
        return (a.toNext or 1e9) < (b.toNext or 1e9)
    end)

    return list
end

-- Everything the clients need once a second: their own progress, and the
-- running order. Six racers, one small table - cheap enough to just send.
function TriRace.publish()
    local order, mine = {}, {}

    for index, entry in ipairs(TriRace.standings()) do
        order[#order + 1] = {
            name     = entry.name,
            position = index,
            finished = entry.finished,
            dnf      = entry.dnf,
            place    = entry.position,
        }

        mine[tostring(entry.src)] = {
            at       = entry.at,
            leg      = entry.leg,
            position = index,
            finished = entry.finished,
            dnf      = entry.dnf,
            place    = entry.position,
        }
    end

    return { order = order, racers = mine, total = #order }
end

-- The window shut. Everyone still out there is a DNF, which is a result in
-- itself and gets read out as one.
function TriRace.dnfRemaining()
    local out = {}

    for _, racer in pairs(racers) do
        if not racer.finished and not racer.dnf then
            racer.dnf = true
            out[#out + 1] = racer.name
        end
    end

    return out
end
