-- The elastic.
--
-- Darren: "provide a little bit of rubber banding so people at the back catch
-- up." A little, and only a little: the leader never gets any, nothing happens
-- until you are properly adrift (banding.BAND_START_M), and the maximum is
-- +20% engine power. That closes a gap which has stopped being a race; it does
-- not out-drag somebody riding cleanly, which would be a worse feeling than
-- losing.
--
-- The gap is measured by the SERVER (server/race.lua publishes `behind`, the
-- straight-line distance to whoever is leading) so nobody's client decides how
-- much help it deserves.
--
-- THE LESSON, PAID FOR IN NICK-OF-TIME (its f54de94): the natives below last
-- exactly ONE FRAME. A multiplier set once, however carefully computed, does
-- literally nothing. Everything here is therefore split in two: a slow thread
-- that DECIDES, and a per-frame thread that does nothing but keep saying it.
local band = {
    value   = 0.0, -- 0 = disengaged; otherwise the engine multiplier
    vehicle = 0,
    onFoot  = false,
    told    = false, -- last engagement state reported to the server
}

-- How much help, for a given gap. Zero until BAND_START_M, then straight-line
-- up to the cap at BAND_FULL_M - a racer should feel it come on gradually as
-- the race gets away from them, not switch on like a light.
local function multiplierFor(behind, max)
    local B = Config.banding
    if not B or not B.ENABLED then return 0.0 end
    if not behind or behind <= (B.BAND_START_M or 150.0) then return 0.0 end

    local from = B.BAND_START_M or 150.0
    local to   = math.max(from + 1.0, B.BAND_FULL_M or 600.0)
    local ramp = math.min(1.0, (behind - from) / (to - from))

    return 1.0 + ((max or B.BAND_MAX or 1.2) - 1.0) * ramp
end

-- Engagement is worth a line in the log, but only when it CHANGES - a print
-- every frame would bury the round. Same shape as nick's bandState.
local function report(engaged, value)
    if not (Config.banding and Config.banding.LOG_CHANGES) then return end
    if engaged == band.told then return end

    band.told = engaged
    TriggerServerEvent('tri:bandState', engaged, value or 0.0)
end

-- ===== the deciding half =====
CreateThread(function()
    while true do
        Wait(500)

        local state = TriState()
        local me    = state.me or {}
        local live  = state.inRace and (state.phase == 'racing' or state.phase == 'runout')
            and not me.finished and not me.dnf

        if not live then
            if band.value > 0.0 then report(false, 0.0) end
            band.value, band.vehicle, band.onFoot = 0.0, 0, false
        else
            local B      = Config.banding or {}
            local legCfg = Config.legs[me.leg or ''] or {}
            local foot   = legCfg.REQUIRE == 'foot'

            local value = multiplierFor(me.behind, foot and B.FOOT_MAX or B.BAND_MAX)

            band.value   = value
            band.onFoot  = foot and value > 0.0
            band.vehicle = (not foot) and GetVehiclePedIsIn(PlayerPedId(), false) or 0

            report(value > 0.0, value)
        end
    end
end)

-- ===== the applying half =====
-- Per frame, or it is not an effect at all. Nothing is computed here. Letting
-- go IS the reset, which is the one kindness of a per-frame native: it cannot
-- leak into free roam or outlive the race.
CreateThread(function()
    while true do
        Wait(0)

        if band.value > 0.0 and band.vehicle ~= 0 and DoesEntityExist(band.vehicle) then
            SetVehicleEnginePowerMultiplier(band.vehicle, band.value)
        elseif band.onFoot then
            -- On foot there is no engine to lean on, so the help is stamina:
            -- the back marker keeps sprinting while the leaders are blowing.
            -- Deliberately weaker than the vehicle boost - a running race
            -- that hands out speed stops being a running race.
            RestorePlayerStamina(PlayerId(), 0.2)
        else
            Wait(250)
        end
    end
end)
