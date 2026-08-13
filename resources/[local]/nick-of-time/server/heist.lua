-- The job itself: what each shop holds, the bag, the alarm, and the stash.
--
-- The server owns all of it, for one reason above the others: the police must
-- never be able to read the robber's live position off a number. A shop's take
-- only becomes public knowledge when the alarm goes off or when he walks out
-- (PUBLIC_VALUE_UPDATE_ON), and a client that never has the live figure cannot
-- leak it.
--
-- This file does not talk. It records what happened and hands the list to
-- round.lua on the next tick, which is the one place that gets to announce
-- things - so the drama stays in one file and the bookkeeping in this one.
NickHeist = {}

local L = Config.looting
local S = Config.safehouses
local E = Config.escalation

local state = {
    sites      = {},  -- this round's loot sites, with what's left in each
    houses     = {},  -- this round's safehouses (seeded, same every round of a session)
    job        = nil, -- { index, method, alarmAt, alarmed }
    carried    = 0,   -- in the bag, lost on arrest or at full time
    stashed    = 0,   -- through a safehouse door: the only number that scores
    taken      = 0,   -- lifted out of shops in total
    publicTaken = 0,  -- ...and how much of that the police have been told about
    events     = {},
}

local function setState(next)
    local merged = {}
    for key, value in pairs(state) do merged[key] = value end
    for key, value in pairs(next) do merged[key] = value end
    state = merged
end

local function push(event)
    local events = {}
    for index, existing in ipairs(state.events) do events[index] = existing end
    events[#events + 1] = event

    setState({ events = events })
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0.0) - (b.z or 0.0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ===== setting the round up =====

-- Every tagged shop is in play, with a till seeded once per session so round
-- four is worth exactly what round one was. The safehouses are a seeded subset
-- of the pool for the same reason - five of the ten, the same five all night,
-- so nobody's turn gets the short walk.
function NickHeist.begin()
    local sites = {}

    for index, site in ipairs(Config.locations.lootSites) do
        local tier  = L.tiers[site.tier or L.DEFAULT_TIER] or L.tiers[L.DEFAULT_TIER]
        local base  = site.stock or (tier and tier.stock) or 0

        -- A little seeded variation so the same shop isn't always the best
        -- shop, without ever being a surprise inside one session.
        local stock = math.floor(base * (0.8 + 0.4 * NickSession.roll(index * 977)))

        sites[index] = {
            name  = site.name or ('site %d'):format(index),
            label = (tier and tier.label) or 'Shop',
            x = site.x, y = site.y, z = site.z,
            stock = stock,
            left  = stock,
        }
    end

    setState({
        sites       = sites,
        houses      = NickSession.pick(Config.locations.safehouses, S.SAFEHOUSE_PER_ROUND, 31),
        job         = nil,
        carried     = 0,
        stashed     = 0,
        taken       = 0,
        publicTaken = 0,
        events      = {},
    })
end

function NickHeist.reset()
    setState({ job = nil, carried = 0, stashed = 0, taken = 0, publicTaken = 0, events = {} })
end

-- What the clients get told at the whistle: where the shops and this round's
-- safehouses are. Stock is deliberately absent - the shops all look the same
-- until you are stood in one.
function NickHeist.map()
    local sites = {}
    for index, site in ipairs(state.sites) do
        sites[index] = { name = site.name, label = site.label, x = site.x, y = site.y, z = site.z }
    end

    local houses = {}
    for index, house in ipairs(state.houses) do
        houses[index] = { name = house.name, x = house.x, y = house.y, z = house.z }
    end

    return { sites = sites, houses = houses }
end

-- ===== the drain =====

-- PUBLIC_VALUE_UPDATE_ON is a policy, not a label: 'alarm_or_exit' tells the
-- police the running total when the bell goes and when he walks out, 'alarm'
-- only when the bell goes, 'never' leaves them entirely in the dark. What it
-- must never be is live - a number that moves while he is stood in a shop is
-- a map pin with extra steps.
local function publish(trigger)
    local when = L.PUBLIC_VALUE_UPDATE_ON

    if when == 'never' then return end
    if when == 'alarm' and trigger ~= 'alarm' then return end

    setState({ publicTaken = state.taken })
end

local function endJob(reason)
    local job = state.job
    if not job then return end

    local site = state.sites[job.index]
    setState({ job = nil })

    -- He's out of the door, so the shopkeeper is on the phone whatever he did
    -- on the way in: this is the "or_exit" half of PUBLIC_VALUE_UPDATE_ON.
    publish('exit')

    push({ kind = 'exit', reason = reason, name = site and site.name, index = job.index })
end

-- Called once a second with the robber's true position (his own client's
-- heartbeat). Everything time-based about a job happens here so there is
-- exactly one clock.
function NickHeist.tick(pos, dt)
    local job = state.job
    if not job or not pos then return end

    local site = state.sites[job.index]
    if not site then return endJob('gone') end

    -- Stepped outside. The bag stops filling immediately - the whole tension
    -- of the mode is deciding, every second, whether to leave with what you
    -- have got.
    if distance(pos, site) > L.ZONE_RADIUS * 1.6 then
        return endJob('left')
    end

    -- The alarm. Instant on a smash-and-grab, on a hidden timer if he came in
    -- quietly - and he is never told which second it is due, because knowing
    -- would turn the choice into arithmetic.
    if not job.alarmed and GetGameTimer() >= job.alarmAt then
        setState({ job = { index = job.index, method = job.method, alarmAt = job.alarmAt, alarmed = true } })
        publish('alarm')
        push({ kind = 'alarm', index = job.index, name = site.name, x = site.x, y = site.y, z = site.z })
    end

    if site.left <= 0 then return endJob('empty') end

    -- Value per second, falling away as the till empties. FILL_RATE_DECAY is
    -- how much of the opening rate survives to the last note: at 0.6 an
    -- almost-empty shop still pays 60%, so a robber who stays to the end is
    -- not stood there for a fiver a second.
    local fraction = site.left / math.max(1, site.stock)
    local rate     = L.FILL_RATE_BASE * (L.FILL_RATE_DECAY + (1.0 - L.FILL_RATE_DECAY) * fraction)

    if job.method == 'smash' then rate = rate * L.SMASH_FILL_MULT end

    local grab = math.min(math.floor(rate * dt), site.left)
    if grab <= 0 then return end

    local sites = {}
    for index, existing in ipairs(state.sites) do sites[index] = existing end
    sites[job.index] = {
        name = site.name, label = site.label,
        x = site.x, y = site.y, z = site.z,
        stock = site.stock, left = site.left - grab,
    }

    setState({ sites = sites, carried = state.carried + grab, taken = state.taken + grab })
end

-- ===== the robber's two decisions =====

-- Through the glass, or through the door. Smash is instant noise for a
-- smaller haul (half the till is in a drawer you are never getting into);
-- quiet is the full stock with a timer you cannot see running.
function NickHeist.startJob(index, method, pos)
    if state.job then return false, 'already at it' end

    local site = state.sites[index]
    if not site then return false, 'no such place' end
    if not pos or distance(pos, site) > L.ZONE_RADIUS * 2.0 then return false, 'not there' end
    if site.left <= 0 then return false, ('%s is cleaned out'):format(site.name) end

    local smash = method == 'smash'
    local band  = L.ALARM_QUIET_BAND_S
    local wait  = smash and L.ALARM_SMASH_DELAY_S or math.random(band[1], band[2])

    -- A smash-and-grab caps what the place will give up at all, for this round
    -- and for anyone who comes back to it later.
    if smash then
        local capped = math.floor(site.left * L.SMASH_TAKE_PCT)
        local sites  = {}
        for i, existing in ipairs(state.sites) do sites[i] = existing end
        sites[index] = {
            name = site.name, label = site.label,
            x = site.x, y = site.y, z = site.z,
            stock = site.stock, left = capped,
        }
        setState({ sites = sites })
    end

    setState({ job = { index = index, method = smash and 'smash' or 'quiet',
                       alarmAt = GetGameTimer() + wait * 1000, alarmed = false } })

    return true
end

-- Only what goes through a safehouse door counts. Everything on him at the
-- moment of an arrest or the whistle is lost, which is the whole reason the
-- last ninety seconds of a round are worth watching.
function NickHeist.stash(index, pos)
    local house = state.houses[index]
    if not house then return false, 'no such place' end
    if not pos or distance(pos, house) > S.ZONE_RADIUS * 1.5 then return false, 'not there' end
    if state.carried <= 0 then return false, 'nothing in the bag' end

    local banked = state.carried
    setState({ carried = 0, stashed = state.stashed + banked })

    if S.SAFEHOUSE_REVEAL_ON_USE then
        push({ kind = 'stash', index = index, name = house.name,
               x = house.x, y = house.y, z = house.z, value = banked })
    end

    return true, banked
end

-- ===== what everyone else needs to know =====

function NickHeist.purse()
    local job  = state.job
    local site = job and state.sites[job.index]

    return {
        carried = state.carried,
        stashed = state.stashed,
        job     = job and {
            name    = site and site.name,
            method  = job.method,
            alarmed = job.alarmed,
            left    = site and site.left or 0,
        } or nil,
    }
end

function NickHeist.stashed()
    return state.stashed
end

function NickHeist.publicTaken()
    return state.publicTaken
end

-- Stars are cosmetic tonight - there are no AI units for them to summon yet -
-- but they are the reason a robber sat on a full bag thinks twice about
-- banking it, because a stash lights up the safehouse he just used.
function NickHeist.stars()
    return math.min(5, math.floor(state.stashed / math.max(1, E.VALUE_PER_STAR)))
end

-- Hand over everything that happened since the last tick, and forget it.
function NickHeist.drain()
    local events = state.events
    setState({ events = {} })
    return events
end
