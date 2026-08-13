-- The next checkpoint, and only the next one.
--
-- Every racer is looking at their own private course: a blip and a route to
-- the one thing they have to reach next, a ring on the ground (or a sphere in
-- the sky) when they are near enough to see it, and nothing at all for the
-- fourteen they have already done or the nine they have not got to. Showing
-- the whole course at once turns a race into a map-reading exercise.
--
-- Arriving is CLAIMED here and DECIDED on the server (server/race.lua). This
-- side does the same checks first purely so the claim is not fired forty times
-- a second by somebody stood in a ring on the wrong vehicle.
local memo = {
    blip      = nil,
    at        = nil, -- which waypoint the blip is for
    sentAt    = 0,   -- last claim, so a slow server round trip is not spammed
    toldAt    = 0,   -- last "you are in the wrong thing" nudge
    heckledAt = nil, -- which waypoint the nudges below are about
    offence   = nil, -- and what for, so a new sin restarts the escalation
    level     = 0,   -- how far up flavour.HECKLES the steward has climbed
}

-- Countdown counts as "showing", so the first checkpoint is already blipped
-- and ringed while everybody is stood on the line looking at it. It does not
-- count as "claiming" - that is the phase check on the arrival loop below.
local SHOWING = { countdown = true, racing = true, runout = true }

local function nextWaypoint()
    local state = TriState()
    if not state.inRace or not state.course then return nil end
    if not SHOWING[state.phase] then return nil end

    local me = state.me or {}
    if me.finished or me.dnf then return nil end

    return state.course.waypoints[me.at or 1]
end

-- Am I allowed to claim this one in what I am currently in? The same question
-- the server asks, asked locally first so the answer can be shown as help text
-- rather than arriving as a mystery. Returns the OFFENCE (a key into
-- flavour.HECKLES) rather than the words, because the words escalate.
local function meets(waypoint)
    local rule = waypoint.require or 'none'
    if rule == 'none' then return true end

    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)

    if rule == 'foot' then
        if not Config.rules.FOOT_CHECK then return true end
        if vehicle ~= 0 then return false, 'FOOT' end
        return true
    end

    if Config.rules.VEHICLE_CHECK == 'off' then return true end

    if vehicle == 0 then return false, 'NEED_VEHICLE' end

    if Config.rules.VEHICLE_CHECK == 'any' then return true end

    if GetEntityModel(vehicle) ~= GetHashKey(waypoint.model or '') then
        return false, 'WRONG_VEHICLE'
    end

    return true
end

local function help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

-- ===== the blip =====

local function clearBlip()
    if memo.blip and DoesBlipExist(memo.blip) then RemoveBlip(memo.blip) end
    memo.blip, memo.at = nil, nil
end

CreateThread(function()
    while true do
        Wait(500)

        local waypoint = nextWaypoint()

        if not waypoint then
            if memo.blip then clearBlip() end
        elseif memo.at ~= waypoint.at then
            clearBlip()

            local blip = AddBlipForCoord(waypoint.coords.x, waypoint.coords.y, waypoint.coords.z)
            SetBlipSprite(blip, Config.hud.BLIP_SPRITE or 1)
            SetBlipColour(blip, waypoint.colour or 5)
            SetBlipScale(blip, Config.hud.BLIP_SCALE or 0.9)
            SetBlipAsShortRange(blip, false)

            -- The line on the map to the next one. It is a race: nobody should
            -- lose it because they were looking at the minimap instead of the
            -- ridge they were about to ride off.
            SetBlipRoute(blip, true)
            SetBlipRouteColour(blip, waypoint.colour or 5)

            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(TriCourse.describe(waypoint))
            EndTextCommandSetBlipName(blip)

            memo.blip, memo.at = blip, waypoint.at
        end
    end
end)

-- ===== the ring =====
-- Drawn only for the one you are going to, and only when you are near enough
-- for it to mean anything. A cylinder on the ground for the legs with ground
-- in them, a sphere for the ones without.
CreateThread(function()
    while true do
        Wait(0)

        local waypoint = nextWaypoint()

        if not waypoint then
            Wait(300)
        else
            local legCfg = Config.legs[waypoint.leg] or {}
            local at     = waypoint.coords
            local me     = GetEntityCoords(PlayerPedId())
            local gap    = #(vector3(at.x, at.y, at.z) - me)

            if gap <= (Config.hud.MARKER_DRAW_DISTANCE or 400.0) then
                local radius = waypoint.radius or 5.0
                local marker = legCfg.MARKER_TYPE or 1
                local alpha  = Config.hud.MARKER_ALPHA or 120

                -- Checkpoint colours match the blip so the ring you can see
                -- and the dot on the map are obviously the same thing.
                local r, g, b = 255, 200, 60
                if waypoint.kind == 'finish' then
                    r, g, b = 255, 80, 80
                elseif waypoint.kind == 'transition' then
                    r, g, b = 120, 255, 160
                end

                if marker == 28 then
                    DrawMarker(28, at.x, at.y, at.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        radius, radius, radius, r, g, b, math.floor(alpha * 0.6),
                        false, false, 2, false, nil, nil, false)
                else
                    DrawMarker(marker, at.x, at.y, at.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        radius * 2.0, radius * 2.0, legCfg.MARKER_HEIGHT or 2.0,
                        r, g, b, alpha, false, false, 2, false, nil, nil, false)
                end
            else
                Wait(200) -- too far to draw: stop burning a frame on it
            end
        end
    end
end)

-- ===== arriving =====
-- Every frame, because a biplane at full chat covers two metres between frames
-- and a gate you can fly through without it counting is worse than no gate.
CreateThread(function()
    while true do
        Wait(0)

        local waypoint = nextWaypoint()
        local phase    = TriState().phase

        if not waypoint or (phase ~= 'racing' and phase ~= 'runout') then
            Wait(300)
        elseif SBM.inRadius(waypoint.coords, waypoint.radius or 5.0) then
            local ok, offence = meets(waypoint)
            local now = GetGameTimer()

            if not ok then
                -- In the ring, in the wrong thing. Say so rather than let them
                -- stand there watching a checkpoint refuse to tick over - and
                -- the longer they stand there, the less polite it gets
                -- (flavour.HECKLES, one rung per nag, sticking on the last).
                local H = Config.flavour.HECKLES or {}

                if now - memo.toldAt > (H.EVERY_S or 3) * 1000 then
                    if memo.heckledAt ~= waypoint.at or memo.offence ~= offence then
                        memo.heckledAt, memo.offence, memo.level = waypoint.at, offence, 0
                    end

                    memo.toldAt = now
                    memo.level  = math.min(memo.level + 1, math.max(#(H[offence] or {}), 1))

                    local line  = (H[offence] or {})[memo.level]
                    local model = waypoint.model or 'vehicle'
                    help(line and line:format(model, model) or 'Not like that.')
                end
            elseif now - memo.sentAt > 600 then
                memo.sentAt = now
                TriggerServerEvent('tri:reached', waypoint.at)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearBlip()
end)
