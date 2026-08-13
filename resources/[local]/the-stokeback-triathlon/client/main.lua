-- Race lifecycle on the racer's own machine: getting placed on the line,
-- being held there for the countdown, and being put back on the course after
-- writing yourself off. The checkpoints, the vehicles and the HUD live in
-- their own files and read state through TriState().
--
-- The placement here is chase's and nick's, near enough word for word: it is
-- the code that stopped players landing in the sky and vehicles landing on
-- their roofs, and both of those cost an evening each.
local state = {
    inRace = false,
    course = nil, -- the flattened course, built from the shared config
    slot   = 1,   -- which peg on the start line is mine
    field  = 1,   -- how many turned up
    phase  = 'idle',
    status = {},  -- the last tri:status
    me     = {},  -- my row out of it: at, leg, position, finished
}

local function setState(next)
    local merged = {}
    for key, value in pairs(state) do merged[key] = value end
    for key, value in pairs(next) do merged[key] = value end
    state = merged
end

-- Read by course.lua, garage.lua and hud.lua.
function TriState()
    return state
end

-- Is there dry ground at this column? The ground probe alone cannot say:
-- over water it answers with the SEABED, because water is not ground -
-- which is exactly how a race vehicle ends up parked under the surf
-- (Darren watched the bike line-up fed to the tide one bay at a time).
-- Everything that PLACES something - the start line pegs here, the
-- garage's vehicle bays - asks this first, per position, at spawn time,
-- so no tag, tonight's or a future one, can ever put a racer or a
-- vehicle below the waterline. Shared through the script environment
-- because a resource cannot call its own exports.
function TriDry(x, y, z)
    local foundWater, water = GetWaterHeightNoWaves(x, y, z + 25.0)
    if not foundWater then return true end

    local foundGround, ground = GetGroundZFor_3dCoord(x, y, z + 25.0, false)
    return ((foundGround and ground) or z) > water
end

TriHUD = {}
TriHUD.notify = SBM.notify
TriHUD.shard  = SBM.shard

function TriHUD.draw(text, x, y, scale)
    SBM.drawText(text, x, y, scale or Config.hud.scale)
end

function TriHUD.clock(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    return ('%d:%02d'):format(math.floor(seconds / 60), seconds % 60)
end

-- 1st, 2nd, 3rd, 4th - the whole reason anybody is out here.
function TriHUD.ordinal(n)
    n = tonumber(n) or 0
    local last, lastTwo = n % 10, n % 100

    if lastTwo >= 11 and lastTwo <= 13 then return n .. 'th' end
    if last == 1 then return n .. 'st' end
    if last == 2 then return n .. 'nd' end
    if last == 3 then return n .. 'rd' end
    return n .. 'th'
end

-- ===== on the line =====

-- Everyone across the start line rather than on top of it, spread from the
-- middle out so the field is centred on the tag wherever it was placed. Uses
-- the tag's own heading: `across` is at right angles to the way they face.
local function placeOnLine(start, slot, field)
    local ped = PlayerPedId()
    local rad = math.rad(start.h or 0.0)
    local rx, ry = math.cos(rad), math.sin(rad)

    local from = ((slot or 1) - (((field or 1) + 1) / 2)) * (Config.vehicles.SLOT_SPACING or 6.0) * 0.5

    -- A peg that lands in the surf collapses toward the tag: a crowded
    -- start line beats a swimmer on it.
    while math.abs(from) > 0.5 and not TriDry(start.x + rx * from, start.y + ry * from, start.z) do
        from = from * 0.5
    end

    SetEntityCoords(ped, start.x + rx * from, start.y + ry * from, start.z, false, false, false, false)
    SetEntityHeading(ped, start.h or 0.0)
    SBM.settleToGround(start.z)
end

RegisterNetEvent('tri:course', function(payload)
    local built = TriCourse.build(payload.course)
    if not built or not built.start then return end

    DoScreenFadeOut(600)
    Wait(700)

    TriGarage.sweep()

    setState({
        inRace = true,
        course = built,
        slot   = payload.slot or 1,
        field  = payload.field or 1,
        me     = { at = 1, leg = Config.LEG_ORDER[1] },
    })

    placeOnLine(built.start, payload.slot, payload.field)

    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
    ClearPedTasksImmediately(ped)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))

    -- Held on the line until the steward says otherwise. The unfreeze is on
    -- tri:go, and also on any end of race, so nobody can be left standing in
    -- a field unable to move - and somebody who turned up after the whistle
    -- is never frozen at all, or they would wait there for a countdown that
    -- has already happened.
    FreezeEntityPosition(ped, payload.hold and true or false)

    DoScreenFadeIn(800)

    TriHUD.shard('THE STOKEBACK TRIATHLON', payload.label or 'Run. Ride. Fly.')

    if not payload.hold then
        TriHUD.notify('~y~Race already gone. Off you go, then.')
    end
end)

RegisterNetEvent('tri:go', function()
    if not state.inRace then return end

    FreezeEntityPosition(PlayerPedId(), false)
    TriHUD.notify('~g~GO.')
end)

RegisterNetEvent('tri:status', function(status)
    if not status then return end

    local mine = status.racers and status.racers[tostring(GetPlayerServerId(PlayerId()))]

    setState({
        phase  = status.phase or 'idle',
        status = status,
        me     = mine or state.me,
    })
end)

RegisterNetEvent('tri:note', function(message)
    TriHUD.notify(tostring(message))
end)

RegisterNetEvent('tri:winner', function(name, seconds)
    if not state.inRace then return end

    if state.me and state.me.finished then
        TriHUD.shard('WINNER', ('%s takes it.'):format(name or '?'))
    else
        TriHUD.shard(('%s WINS'):format(string.upper(name or '?')),
            ('%d seconds to get yourself over the line.'):format(seconds or 60))
    end
end)

RegisterNetEvent('tri:end', function(result, winner, standings)
    -- A fresh table, NOT setState: a key written as nil in a constructor is
    -- simply absent from a merge, so `course = nil` would have left every loop
    -- in this resource still believing there was a race on - drawing markers
    -- and stripping weapons in free roam forever after. nick paid for this one.
    state = { inRace = false, course = nil, slot = 1, field = 1, phase = 'idle', status = {}, me = {} }

    FreezeEntityPosition(PlayerPedId(), false)
    TriGarage.sweep(true) -- gently: somebody is probably still flying

    local shards = {
        finished  = { 'RACE OVER', ('%s wins the Stokeback Triathlon.'):format(winner or '?') },
        time      = { 'TIME', 'Twenty minutes. That will do.' },
        abandoned = { 'RACE ABANDONED', 'The steward has gone for a pint.' },
    }

    local shard = shards[result] or shards.abandoned
    TriHUD.shard(shard[1], shard[2])

    -- The ceremony (hud.lua): gold, silver, bronze and a sponsor, once the
    -- shard above has had its moment.
    if TriPodium then TriPodium.show(standings) end
end)

-- The camera says what the eye could not. Everyone gets the card - a photo
-- finish with no audience is just two aeroplanes.
RegisterNetEvent('tri:photo', function(first, second, gap)
    if not state.inRace then return end

    local P = Config.flavour.PHOTO or {}
    TriHUD.shard(P.SHARD or 'PHOTO FINISH',
        ('%s pips %s by %.2f seconds.'):format(first or '?', second or '?', gap or 0))
end)

-- ===== putting people back on the course =====

-- Death, a bike in a lake, a biplane in a hillside: none of it takes anybody
-- out of the race. Back to the last thing you actually reached, with a fresh
-- vehicle if the leg calls for one.
--
-- The one case that is NOT a teleport is a pilot who has already been through
-- a gate: the garage puts a plane in the air at that gate with the engine
-- running and warps him into it, because a crash that ends in a two minute
-- climb back to altitude has ended his race anyway.
function TriBackToCheckpoint()
    if not state.inRace or not state.course then return end
    if state.me and (state.me.finished or state.me.dnf) then return end
    if not Config.respawn.AT_LAST_CHECKPOINT then return end

    local at     = state.me and state.me.at or 1
    local last   = state.course.waypoints[at - 1]
    local legCfg = Config.legs[state.me and state.me.leg or ''] or {}
    local needs  = legCfg.REQUIRE == 'vehicle'
    local inAir  = needs and (state.me.leg == 'air') and last and last.kind == 'cp'

    DoScreenFadeOut(500)
    Wait(600)

    if not inAir then
        local back = (last and last.coords) or state.course.start
        if back then
            local ped = PlayerPedId()
            SetEntityCoords(ped, back.x, back.y, back.z, false, false, false, false)
            SetEntityHeading(ped, back.h or GetEntityHeading(ped))
            SBM.settleToGround(back.z)
        end
    end

    if needs then
        TriGarage.request()
        Wait((Config.vehicles.REPLACE_DELAY_S or 3) * 1000)
    end

    -- The respawn penalty, if anybody ever votes one in: held in place at the
    -- checkpoint for a beat before being let go again. Zero by default - the
    -- scope is emphatic that crashing is not meant to end anybody's evening.
    if (Config.respawn.PENALTY_S or 0) > 0 then
        local ped = PlayerPedId()
        FreezeEntityPosition(ped, true)
        DoScreenFadeIn(700)
        Wait(Config.respawn.PENALTY_S * 1000)
        FreezeEntityPosition(ped, false)
        return
    end

    DoScreenFadeIn(700)
end

-- The death watch. core's respawn policy (declared on the descriptor) is what
-- actually stands them back up where they fell; this notices that it has
-- happened and moves them to somewhere that makes sense for a race.
CreateThread(function()
    local wasDead = false

    while true do
        Wait(500)

        if state.inRace and (state.phase == 'racing' or state.phase == 'runout'
            or state.phase == 'countdown') then

            local ped  = PlayerPedId()
            local dead = IsEntityDead(ped) or IsPedFatallyInjured(ped)

            if dead then
                wasDead = true
            elseif wasDead then
                wasDead = false

                if state.phase == 'countdown' then
                    -- Run over ON THE LINE - population 'alive' means the
                    -- number 19 bus is a real hazard. core's respawn stood
                    -- them up as a brand new, unfrozen ped wherever they
                    -- fell: back on their peg and frozen again, or a death
                    -- at 'three' is a head start at 'go'.
                    if state.course and state.course.start then
                        placeOnLine(state.course.start, state.slot, state.field)
                        -- Re-checked AFTER placing: placeOnLine waits on
                        -- collision, and GO may have come and gone meanwhile
                        -- - a freeze then would hold them past the whistle.
                        FreezeEntityPosition(PlayerPedId(), state.phase == 'countdown')
                    end
                else
                    TriBackToCheckpoint()
                end
            end
        else
            wasDead = false
        end
    end
end)

-- "My bike is in a lake." Genuinely held, not tapped - a tap teleports you
-- back a checkpoint, and G sits next to too many keys people lean on
-- mid-jump. The hold length is a config knob; the server still decides
-- whether a replacement is actually granted.
local function hint(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

CreateThread(function()
    local heldAt = nil

    while true do
        Wait(0)

        local legCfg = state.inRace and Config.legs[state.me and state.me.leg or ''] or nil

        if legCfg and legCfg.REQUIRE == 'vehicle'
            and (state.phase == 'racing' or state.phase == 'runout')
            and not (state.me and state.me.finished) then

            if IsControlPressed(0, Config.controls.RECOVER) then
                heldAt = heldAt or GetGameTimer()

                if GetGameTimer() - heldAt >= (Config.controls.RECOVER_HOLD_S or 1.0) * 1000 then
                    heldAt = nil
                    TriBackToCheckpoint()
                else
                    hint('Keep holding to write this one off and take a replacement.')
                end
            else
                heldAt = nil
            end
        else
            heldAt = nil
            Wait(400)
        end
    end
end)

-- ===== house rules =====
-- No weapons, and whatever the room has voted for on stamina and on players
-- being able to walk through each other.
CreateThread(function()
    while true do
        Wait(1000)

        if state.inRace then
            if Config.rules.NO_WEAPONS then
                RemoveAllPedWeapons(PlayerPedId(), true)
            end

            if Config.rules.INFINITE_STAMINA then
                RestorePlayerStamina(PlayerId(), 1.0)
            end

            -- Off by default: the scope is explicit that normal collision
            -- stays on and that arguing about whose fault it was is half the
            -- entertainment. This is the knob for the week somebody snaps.
            if not Config.rules.PLAYER_COLLISION then
                local me = PlayerPedId()

                for _, id in ipairs(GetActivePlayers()) do
                    if id ~= PlayerId() then
                        local other = GetPlayerPed(id)
                        if DoesEntityExist(other) then
                            SetEntityNoCollisionEntity(me, other, true)
                        end
                    end
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    FreezeEntityPosition(PlayerPedId(), false)
    TriGarage.sweep()
end)
