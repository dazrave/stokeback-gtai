-- Detection: hard lock, drifting soft track, cold. The one piece of this mode
-- that has to be right before anything else matters.
--
-- All of it lives on the SERVER, deliberately. Every client would otherwise
-- extrapolate its own guess and two coppers stood next to each other would be
-- searching different circles - and the whole feeling depends on the force
-- sharing one wrong idea about where he is.
--
--   hard   a copper has eyes on him RIGHT NOW. The dot is the truth.
--   soft   nobody can see him. The dot keeps going the way he was last seen
--          going, slowing down as the guess ages, with the circle swelling
--          around it. Doubling back behind a building is therefore free: the
--          circle carries on the wrong way and the police follow it.
--   cold   the circle got so big it stopped being information. Nothing on the
--          map at all. Alarms and 999 calls are the only way back in.
--
-- Chase's sighting machinery is the ancestor of this file, but chase ended up
-- publishing the fugitive's live position permanently (`trackPos`) - which is
-- the exact opposite of this mode's acceptance criterion, so the drift below
-- is written fresh.
NickDetect = {}

local D = Config.detection

local state = {
    contact     = 'cold',
    via         = nil, -- what produced the last sighting: eyes | patrol | air
    lastSeen    = nil, -- truth, as at the last sighting
    lastSeenAt  = 0,
    heading     = nil, -- degrees, the way he was travelling between sightings
    speed       = 0.0, -- m/s, likewise
    ghost       = nil, -- where the police THINK he is
    radius      = 0.0,
    confidence  = 0.0, -- how much of that heading we still believe
    maxUnseenMs = 0,   -- his longest single vanishing act, for the retelling
}

local function setState(next)
    local merged = {}
    for key, value in pairs(state) do merged[key] = value end
    for key, value in pairs(next) do merged[key] = value end
    state = merged
end

-- A new round is a new state, not a patch on the old one - chase lost an
-- evening to a merged `lastSeen = nil` surviving into the next round and
-- ending it at the whistle.
function NickDetect.reset()
    state = {
        contact     = 'cold',
        via         = nil,
        lastSeen    = nil,
        lastSeenAt  = 0,
        heading     = nil,
        speed       = 0.0,
        ghost       = nil,
        radius      = 0.0,
        confidence  = 0.0,
        maxUnseenMs = 0,
    }
end

-- GTA's compass, spelled out once: heading 0 faces +Y (north) and increases
-- anticlockwise, so the forward vector is (-sin, cos) and the heading of a
-- movement is atan2(-dx, dy). Getting this backwards would send the search
-- circle off in precisely the wrong direction, which is a bug you cannot see
-- in a test and can only feel in a round.
local function headingOf(dx, dy)
    return math.deg(math.atan(-dx, dy)) % 360.0
end

local function forwardOf(heading)
    local rad = math.rad(heading)
    return -math.sin(rad), math.cos(rad)
end

-- Somebody has him. ONE detection rule (pillar 1): a copper's raycast, a
-- patrol car's proximity relay and the bonus helicopter's ping all arrive
-- here, all snap the guess back onto the truth, and all decay through the same
-- drifting circle the moment they stop. `via` only changes what the HUD calls
-- it - "eyes on" and "a patrol has him" should never feel identical, even
-- though the map treats them the same.
function NickDetect.sighting(coords, via)
    local now = GetGameTimer()

    local heading, speed = state.heading, state.speed
    local maxUnseen = state.maxUnseenMs

    if state.lastSeen then
        local dt = (now - state.lastSeenAt) / 1000.0
        local dx = coords.x - state.lastSeen.x
        local dy = coords.y - state.lastSeen.y
        local gap = math.sqrt(dx * dx + dy * dy)

        -- Ignore standing still and ignore samples too close together to mean
        -- anything: a pair of pings 40ms apart turns a metre of net jitter
        -- into 25 m/s and flings the circle across the map.
        if dt >= 0.15 and gap > 1.0 then
            heading = headingOf(dx, dy)
            speed   = math.min(gap / dt, D.SOFT_TRACK_MAX_DRIFT_MPS)
        end

        -- The vanishing act that just ended, if it beats his record.
        local unseen = now - state.lastSeenAt
        if unseen > maxUnseen then maxUnseen = unseen end
    end

    setState({
        contact     = 'hard',
        via         = via or 'eyes',
        lastSeen    = { x = coords.x, y = coords.y, z = coords.z },
        lastSeenAt  = now,
        heading     = heading,
        speed       = speed,
        ghost       = { x = coords.x, y = coords.y, z = coords.z },
        radius      = D.SOFT_TRACK_BASE_RADIUS,
        confidence  = 1.0,
        maxUnseenMs = maxUnseen,
    })
end

-- One step of the guess. `dt` is seconds since the last step - the framework
-- ticks us at ~1Hz, which is plenty for something that is wrong on purpose.
function NickDetect.tick(dt)
    if not state.lastSeen then return end -- never seen this round: stay cold

    local since = GetGameTimer() - state.lastSeenAt

    -- Still being looked at (or looked at within the grace, so a lamppost
    -- passing between two cars doesn't flick the whole force onto a guess).
    if since <= D.LOS_GRACE_MS then
        if state.contact ~= 'hard' then setState({ contact = 'hard' }) end
        return
    end

    if state.contact == 'cold' then return end

    -- Carry the guess forward at the speed he was doing, fading as it ages:
    -- the first few seconds of a soft track are worth chasing, half a minute
    -- of one is a wild stab that has quietly stopped moving.
    local fx, fy = forwardOf(state.heading or 0.0)
    local step   = state.speed * state.confidence * dt

    local ghost = {
        x = state.ghost.x + fx * step,
        y = state.ghost.y + fy * step,
        z = state.ghost.z,
    }

    local radius     = state.radius + D.SOFT_TRACK_GROWTH_MPS * dt
    local confidence = state.confidence * (D.SOFT_TRACK_DRIFT_DECAY ^ dt)

    if radius >= D.SOFT_TRACK_COLD_RADIUS then
        -- Past here the circle covers half a borough. Better to admit they
        -- have lost him than to leave a lie on the map.
        setState({ contact = 'cold', ghost = nil, radius = 0.0, confidence = 0.0 })
        return
    end

    setState({ contact = 'soft', ghost = ghost, radius = radius, confidence = confidence })
end

-- What the police are told. Note what is NOT in here: his real position,
-- unless somebody is currently looking at him.
function NickDetect.publish()
    local unseenFor = state.lastSeen
        and math.floor((GetGameTimer() - state.lastSeenAt) / 1000)
        or nil

    if state.contact == 'hard' then
        return {
            contact   = 'hard',
            via       = state.via or 'eyes',
            track     = state.lastSeen,
            radius    = 0.0,
            heading   = state.heading,
            unseenFor = unseenFor,
        }
    end

    if state.contact == 'soft' then
        return {
            contact   = 'soft',
            track     = state.ghost,
            radius    = state.radius,
            heading   = state.heading,
            unseenFor = unseenFor,
        }
    end

    return { contact = 'cold', unseenFor = unseenFor }
end

function NickDetect.contact()
    return state.contact
end

-- For the end-of-round retelling: how invisible was he, really. The streak
-- still running at the whistle counts - going dark at 4:00 and staying dark
-- is the best version of the story.
function NickDetect.review()
    local ongoing = state.lastSeen and (GetGameTimer() - state.lastSeenAt) or 0

    return {
        everSeen       = state.lastSeen ~= nil,
        longestUnseenS = math.floor(math.max(state.maxUnseenMs, ongoing) / 1000),
    }
end
