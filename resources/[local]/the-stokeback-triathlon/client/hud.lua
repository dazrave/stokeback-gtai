-- One line, top centre: the clock, which discipline you are in, how far
-- through it you are, and - the only number anybody actually reads - what
-- position you are lying in.
--
-- Plus the countdown, which is the whole start of the race: six people frozen
-- on a line watching a number, which is considerably more tense than it has
-- any right to be.
local function progressLine(state, status, me)
    local waypoint = state.course and state.course.waypoints[me.at or 1] or nil

    local where
    if me.finished then
        where = ('~g~FINISHED %s'):format(TriHUD.ordinal(me.place or 1))
    elseif me.dnf then
        where = '~r~DNF'
    else
        where = ('~y~%s'):format(TriCourse.describe(waypoint))
    end

    return ('%s   %s   ~w~%s of %d'):format(
        TriHUD.clock(status.remaining),
        where,
        TriHUD.ordinal(me.position or 1),
        status.total or 1)
end

CreateThread(function()
    while true do
        Wait(0)

        local state = TriState()

        if not state.inRace then
            Wait(400)
        else
            local status = state.status or {}
            local me     = state.me or {}

            if state.phase == 'countdown' then
                local seconds = status.countdown

                if not seconds then
                    -- Still being placed: the server has not armed the real
                    -- count yet, and the provisional deadline it holds in the
                    -- meantime is not a number anybody should see.
                    TriHUD.draw(Config.flavour.READY_LINE or 'Hold.', 0.5, 0.34, 0.8)
                else
                    -- The last three get their own size, because everybody
                    -- leans forward for them.
                    TriHUD.draw(seconds > 0 and tostring(seconds) or 'GO',
                        0.5, 0.34, seconds > 0 and seconds <= 3 and 2.2 or 1.6)
                end

                TriHUD.draw('~y~Run. Ride. Fly. In that order.', 0.5, 0.46, 0.5)

            elseif state.phase == 'racing' or state.phase == 'runout' then
                TriHUD.draw(progressLine(state, status, me), Config.hud.x, Config.hud.y)

                -- The sixty seconds. Everybody sees it, including the winner,
                -- who has earned the right to watch it run down on the rest.
                if status.runout then
                    TriHUD.draw(('~r~FINISH WINDOW %s~w~ - %s has it'):format(
                        TriHUD.clock(status.runout), status.winner or '?'),
                        Config.hud.x, Config.hud.y + 0.038, Config.hud.scale * 0.9)
                end
            else
                Wait(200)
            end
        end
    end
end)

-- ===== the podium =====
-- Gold, silver, bronze and a sponsor nobody has heard of (flavour.PODIUM),
-- drawn once the end shard has had its moment. Drawn rather than chatted,
-- because a ceremony you can screenshot beats one that scrolls away.
TriPodium = {}

local ceremony = nil -- { from, showUntil, rows, sponsor }

function TriPodium.show(standings)
    local P = Config.flavour.PODIUM
    if not P or type(standings) ~= 'table' then return end

    local rows = {}
    for _, entry in ipairs(standings) do
        if entry.finished and #rows < #(P.MEDALS or {}) then
            local medal = P.MEDALS[#rows + 1]
            rows[#rows + 1] = ('%s%s~w~   %s   %s'):format(
                medal.tint or '~w~', medal.label or '?', entry.name,
                TriHUD.clock(math.floor((entry.time or 0) / 1000)))
        end
    end

    if #rows == 0 then return end -- nobody finished: no ceremony, just shame

    local now = GetGameTimer()
    ceremony = {
        from      = now + (P.DELAY_S or 6.5) * 1000,
        showUntil = now + ((P.DELAY_S or 6.5) + (P.SECONDS or 12)) * 1000,
        rows      = rows,
        sponsor   = (P.SPONSORS and #P.SPONSORS > 0)
            and (P.SPONSOR_LINE or 'Brought to you by %s.'):format(
                P.SPONSORS[math.random(#P.SPONSORS)])
            or nil,
    }
end

CreateThread(function()
    while true do
        Wait(0)

        local now = GetGameTimer()

        -- `not inRace`: a new race started inside the ceremony window takes
        -- the stage; nobody needs last race's podium over this race's line.
        if ceremony and now >= ceremony.from and now < ceremony.showUntil
            and not TriState().inRace then
            TriHUD.draw(Config.flavour.PODIUM.TITLE or 'THE PODIUM', 0.5, 0.30, 0.9)

            local y = 0.38
            for _, row in ipairs(ceremony.rows) do
                TriHUD.draw(row, 0.5, y, 0.6)
                y = y + 0.045
            end

            if ceremony.sponsor then
                TriHUD.draw('~c~' .. ceremony.sponsor, 0.5, y + 0.02, 0.42)
            end
        elseif ceremony and now >= ceremony.showUntil then
            ceremony = nil
        else
            Wait(250)
        end
    end
end)

-- The running order, down the left, while a race is on. Six names is a
-- scoreboard; it is also the thing that makes somebody who is losing take the
-- ridge at a stupid angle, which is the point of showing it.
CreateThread(function()
    while true do
        Wait(0)

        local state  = TriState()
        local status = state.status or {}

        if state.inRace and (state.phase == 'racing' or state.phase == 'runout')
            and status.order then

            local y = 0.30

            for index, entry in ipairs(status.order) do
                local tint = '~w~'
                if entry.finished then tint = '~g~' elseif entry.dnf then tint = '~r~' end

                SetTextFont(4)
                SetTextScale(0.34, 0.34)
                SetTextColour(255, 255, 255, 200)
                SetTextOutline()
                SetTextCentre(false) -- said out loud: SBM.drawText leaves it on

                BeginTextCommandDisplayText('STRING')
                AddTextComponentSubstringPlayerName(('%s%d. %s'):format(tint, index, entry.name))
                EndTextCommandDisplayText(0.015, y)

                y = y + 0.026
                if index >= 8 then break end -- a scoreboard, not a phone book
            end
        else
            Wait(300)
        end
    end
end)
