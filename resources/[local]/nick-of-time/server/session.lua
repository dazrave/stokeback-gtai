-- The session: the seed, the scoreboard, and the "have we got a map yet"
-- gate. Everything in here has to outlive a resource restart, because PUSH
-- LIVE bounces this resource several times an evening and a match is N rounds
-- long - a scoreboard that resets when an agent deploys a fix is not a
-- scoreboard.
--
-- A global rather than an export: every file here runs in the same resource,
-- and a resource cannot call its own exports.
NickSession = {}

local FILE = '.session'

local function load()
    local raw = LoadResourceFile(GetCurrentResourceName(), FILE)
    if not raw or raw == '' then return nil end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return nil end

    -- A session is one evening. A file that has outlived the age cap is LAST
    -- week's match - replaying its seed against its scoreboard would make
    -- tonight's rounds a contest with ghosts - so it is quietly retired and
    -- a fresh session starts.
    local age = os.time() - (decoded.startedAt or 0)
    if age > (Config.round.SESSION_MAX_AGE_H or 18) * 3600 then return nil end

    return decoded
end

local function save(data)
    SaveResourceFile(GetCurrentResourceName(), FILE, json.encode(data), -1)
end

-- Read once on the way up, then kept in memory. `scores` is by NAME, not by
-- server id: ids are handed out fresh on every reconnect and would lose a
-- player their whole evening the moment their game crashed.
local session = load() or {
    seed       = math.random(1, 2147483000),
    scores     = {},
    lastRobber = nil,
    startedAt  = os.time(),
}
if type(session.scores) ~= 'table' then session.scores = {} end

-- ===== fairness: one seed for the whole session =====
-- "Loot values, cop spawns, safehouse selection, clock and weather are seeded
-- once per session and reused identically for every round." So every pick the
-- mode makes comes out of THIS, never out of math.random - otherwise round
-- four gets an easier map than round one and the scoreboard means nothing.
--
-- A tiny Lehmer generator rather than math.randomseed: seeding the global RNG
-- would quietly change every other random thing in the round, and we want a
-- pure function of (seed, salt) we can call again and get the same answer.
local function stream(seed)
    local s = seed % 2147483647
    if s <= 0 then s = s + 2147483646 end

    return function()
        s = (s * 16807) % 2147483647
        return s / 2147483647
    end
end

function NickSession.seed()
    return session.seed
end

-- A deterministic subset: the same list, seed and salt always give the same
-- picks in the same order. Never mutates the caller's table - it shuffles a
-- copy of the indices.
function NickSession.pick(list, count, salt)
    local out = {}
    if type(list) ~= 'table' or #list == 0 then return out end

    local order = {}
    for index = 1, #list do order[index] = index end

    local next_ = stream(session.seed + (salt or 0))

    for index = #order, 2, -1 do
        local swap = math.floor(next_() * index) + 1
        order[index], order[swap] = order[swap], order[index]
    end

    for index = 1, math.min(count or #order, #order) do
        out[#out + 1] = list[order[index]]
    end

    return out
end

-- One deterministic number in [0,1) for a named thing, so a site's value can
-- be jittered identically every round without a table of pre-rolled numbers.
function NickSession.roll(salt)
    return stream(session.seed + (salt or 0))()
end

-- ===== the scoreboard =====
function NickSession.record(name, stashed)
    if not name or name == '' then return end

    local scores = {}
    for player, total in pairs(session.scores) do scores[player] = total end
    scores[name] = (scores[name] or 0) + math.floor(stashed or 0)

    session = { seed = session.seed, scores = scores,
                lastRobber = session.lastRobber, startedAt = session.startedAt }
    save(session)
end

function NickSession.leader()
    local best, bestTotal = nil, 0

    for name, total in pairs(session.scores) do
        if total > bestTotal then best, bestTotal = name, total end
    end

    if not best then return nil end
    return { name = best, total = bestTotal }
end

function NickSession.totalFor(name)
    return session.scores[name] or 0
end

-- ===== whose turn it is =====
-- Everyone takes a turn as the robber and nobody goes twice on the bounce.
-- Kept on disk with the scores for the same reason: a restart mid-match must
-- not hand the same player two goes.
function NickSession.rememberRobber(name)
    session = { seed = session.seed, scores = session.scores,
                lastRobber = name, startedAt = session.startedAt }
    save(session)
end

function NickSession.lastRobber()
    return session.lastRobber
end

-- ===== the map gate =====
-- Zero locations are tagged, and a coordinate may never be guessed (AGENTS.md,
-- and every time it has been ignored somebody has spawned inside a wall). So
-- the mode ships complete and simply refuses to deal until the tag board has
-- caught up.
function NickSession.missing()
    local gaps = {}

    for _, need in ipairs(Config.locationNeeds) do
        local have = #(Config.locations[need.key] or {})

        if have < need.min then
            gaps[#gaps + 1] = {
                label = need.label,
                have  = have,
                min   = need.min,
                want  = need.want,
                tag   = need.tag,
            }
        end
    end

    return gaps
end
