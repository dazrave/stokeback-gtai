-- The course, flattened.
--
-- A race is really one ordered list of things to reach: eight running
-- checkpoints, then the bikes, then nine motocross checkpoints, then the
-- planes, then seven gates, then the line. Both halves of the mode need that
-- list and they need it IDENTICAL - the client decides "I am in the ring and I
-- claim number 12" and the server decides whether number 12 is where he says
-- it is - so it is built here, from the config, by the same function on both
-- sides. A shared script rather than two copies, because two copies of an
-- ordered list is a bug with a schedule.
--
-- A global rather than an export: this file is loaded into the mode's own
-- script environment, and a resource cannot call its own exports anyway.
TriCourse = {}

-- A tagged point, or nil if the tag board has not caught up. Coerced to
-- numbers so a config edited by hand ("z = 30") cannot produce a vector the
-- natives quietly refuse.
local function point(entry, lift)
    if type(entry) ~= 'table' then return nil end
    if entry.x == nil or entry.y == nil or entry.z == nil then return nil end

    return {
        name = entry.name,
        x = entry.x + 0.0,
        y = entry.y + 0.0,
        z = entry.z + 0.0 + (lift or 0.0),
        h = (entry.h or 0.0) + 0.0,
    }
end

local function points(list, lift)
    local out = {}
    for _, entry in ipairs(list or {}) do
        local at = point(entry, lift)
        if at then out[#out + 1] = at end
    end
    return out
end

function TriCourse.get(name)
    return Config.courses[name or Config.COURSE]
end

-- What a need points at: either a field on the course itself (`start`) or a
-- field on one of its legs. Shared by the builder and by the refusal message
-- so they can never disagree about what "tagged" means.
function TriCourse.have(course, need)
    if not course then return 0 end

    local value
    if need.leg then
        value = (course.legs and course.legs[need.leg] or {})[need.field]
    else
        value = course[need.field]
    end

    if type(value) ~= 'table' then return 0 end
    if value.x ~= nil then return 1 end -- a single tagged point

    local count = 0
    for _, entry in ipairs(value) do
        if point(entry) then count = count + 1 end
    end
    return count
end

-- The map gate. Everything still missing, in the order it needs walking.
function TriCourse.missing(name)
    local course = TriCourse.get(name)
    local gaps   = {}

    for _, need in ipairs(Config.courseNeeds) do
        local have = TriCourse.have(course, need)

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

-- The whole race as one ordered list.
--
-- The awkward one is the transition. It is the first thing in a vehicle leg,
-- but you arrive at it under the PREVIOUS leg's rules - on foot to the bikes,
-- on the bike to the planes - and the scope is explicit that you physically
-- reach the next vehicle rather than being teleported into it. So a transition
-- waypoint carries the previous leg's radius, no vehicle requirement at all
-- (a rider whose bike is in a lake may walk the last of it), and an `opens`
-- field: reaching it is what starts the next discipline and puts a vehicle in
-- front of you.
function TriCourse.build(name)
    local course = TriCourse.get(name)
    if not course then return nil end

    local waypoints, totals = {}, {}

    for legIndex, leg in ipairs(Config.LEG_ORDER) do
        local legCfg = Config.legs[leg] or {}
        local data   = (course.legs or {})[leg] or {}
        local lift   = legCfg.GATE_HEIGHT_OFFSET or 0.0

        local previous   = Config.LEG_ORDER[legIndex - 1]
        local transition = point(data.transition)

        if previous and transition then
            local prevCfg = Config.legs[previous] or {}

            waypoints[#waypoints + 1] = {
                leg     = previous,
                kind    = 'transition',
                opens   = leg,
                coords  = transition,
                -- The OPENING leg's knob first: TRANSITION_RADIUS is written
                -- in config as "arriving at the bikes/planes", i.e. it belongs
                -- to the leg whose vehicles are parked there. Previous-first
                -- made air's 8.0 unreachable behind moto's 6.0.
                radius  = legCfg.TRANSITION_RADIUS or prevCfg.TRANSITION_RADIUS or prevCfg.RADIUS,
                require = 'none',
                label   = legCfg.TRANSITION_LABEL or 'the transition',
                colour  = legCfg.BLIP_COLOUR,
                -- Always: you arrive at a line of parked vehicles physically,
                -- on the ground, whatever leg they belong to.
                grounded = true,
            }
        end

        local checkpoints = points(data.checkpoints, lift)
        totals[leg] = #checkpoints

        -- Stamped here, from the leg's config, so the client's ground probe
        -- and the server's flat distance check can never disagree about
        -- which waypoints live on the terrain. Only a leg that explicitly
        -- says GROUNDED = false (the air gates) keeps its configured z as
        -- gospel; everything else treats z as advisory and the ground as
        -- the authority.
        local grounded = legCfg.GROUNDED ~= false

        for index, at in ipairs(checkpoints) do
            waypoints[#waypoints + 1] = {
                leg     = leg,
                kind    = 'cp',
                index   = index,
                of      = #checkpoints,
                coords  = at,
                radius  = legCfg.RADIUS,
                require = legCfg.REQUIRE,
                model   = legCfg.MODEL,
                label   = ('%s %d/%d'):format(legCfg.CHECKPOINT_WORD or 'checkpoint', index, #checkpoints),
                colour  = legCfg.BLIP_COLOUR,
                grounded = grounded,
            }
        end

        local finish = point(data.finish, lift)
        if finish then
            waypoints[#waypoints + 1] = {
                leg     = leg,
                kind    = 'finish',
                coords  = finish,
                radius  = legCfg.RADIUS,
                require = legCfg.REQUIRE,
                model   = legCfg.MODEL,
                label   = 'THE FINISH',
                colour  = 1, -- red: the only one that ends anything
                grounded = grounded,
            }
        end
    end

    -- Its own index, stamped on: the number a client claims and the number the
    -- server checks are the same number.
    for index, waypoint in ipairs(waypoints) do waypoint.at = index end

    return {
        name      = name or Config.COURSE,
        label     = course.label or 'The course',
        start     = point(course.start),
        waypoints = waypoints,
        totals    = totals,
    }
end

-- How far along, said out loud. Used by the HUD and by the standings when
-- nobody finishes and the round is scored on progress.
function TriCourse.describe(waypoint)
    if not waypoint then return 'finished' end

    local legCfg = Config.legs[waypoint.leg] or {}
    local label  = legCfg.LABEL or waypoint.leg

    if waypoint.kind == 'transition' then
        return ('%s - to %s'):format(label, waypoint.label)
    elseif waypoint.kind == 'finish' then
        return ('%s - %s'):format(label, waypoint.label)
    end

    return ('%s - %s'):format(label, waypoint.label)
end
