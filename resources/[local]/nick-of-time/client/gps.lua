-- Auto-GPS. Plan §5.6: the route line always points at the best thing
-- currently known, which is very often NOT the suspect - it is a shop with a
-- bell ringing in it, or a 999 call from ninety seconds ago, or the one
-- convenience store on this side of the river he has not been in yet.
--
-- Strict priority with hysteresis. The ladder never reorders, but a target has
-- to hold for HOLD_MS before a same-or-lower priority one can take it: two
-- near-equal leads would otherwise swap the route every tick and turn the
-- minimap into a strobe light, which is worse than no routing at all.
--
-- One owner. police.lua deliberately does not set routes - the whole point of
-- a priority ladder is that exactly one thing decides.
local G = Config.gps

-- Lower number wins. Written out rather than implied by table order, because
-- this list IS the design and somebody will want to argue with it.
local PRIORITY = {
    lock    = 1, -- somebody has him. Nothing beats going where he is.
    alarm   = 2, -- a bell is ringing. He was there seconds ago.
    witness = 3, -- a member of the public saw something, a while back.
    soft    = 4, -- the drifting guess. Better than nothing, and often wrong.
    site    = 5, -- the nearest shop he has not emptied. A prediction, not a lead.
}

local route = { blip = nil, kind = nil, at = 0, x = 0, y = 0 }
local leads = {}   -- recent alarms and witness calls, newest last
local manualUntil = 0

local function clearRoute()
    if route.blip and DoesBlipExist(route.blip) then RemoveBlip(route.blip) end
    route = { blip = nil, kind = nil, at = 0, x = 0, y = 0 }
end

-- The leads the police have been handed. Kept here rather than read out of
-- police.lua's blip list so the ladder depends on the FACTS, not on whether a
-- blip happens to still be on the map.
RegisterNetEvent('nick:ping', function(kind, at)
    local role = NickState()
    if role ~= 'police' then return end
    if kind ~= 'alarm' and kind ~= 'witness' then return end

    leads[#leads + 1] = { kind = kind, x = at.x, y = at.y, z = at.z, at = GetGameTimer() }
end)

RegisterNetEvent('nick:end', function()
    leads = {}
    clearRoute()
end)

-- The freshest lead of a kind, if it is still worth driving at. An alarm stays
-- interesting for as long as its blip lives; a witness call goes stale fast,
-- because a point somebody phoned in a minute ago is just a place he isn't.
local function freshest(kind, maxAgeMs)
    local best = nil

    for _, lead in ipairs(leads) do
        if lead.kind == kind and (GetGameTimer() - lead.at) < maxAgeMs then
            if not best or lead.at > best.at then best = lead end
        end
    end

    return best
end

-- The nearest shop the police KNOW he has not emptied. status.emptySites only
-- updates when the money does (alarm or exit), so this routes on what the
-- force actually knows rather than on the truth.
local function nearestUnhit(status)
    local sites = NickMap().sites or {}
    if #sites == 0 then return nil end

    local empty = {}
    for _, index in ipairs(status.emptySites or {}) do empty[index] = true end

    local me = GetEntityCoords(PlayerPedId())
    local best, bestGap = nil, nil

    for index, site in ipairs(sites) do
        if not empty[index] then
            local gap = #(vector3(site.x, site.y, site.z) - me)
            if not bestGap or gap < bestGap then best, bestGap = site, gap end
        end
    end

    return best
end

local function pick(status)
    if status.contact == 'hard' and status.track then
        return 'lock', status.track
    end

    local alarm = freshest('alarm', Config.escalation.PING_LIFE_MS)
    if alarm then return 'alarm', alarm end

    local witness = freshest('witness', G.WITNESS_FRESH_S * 1000)
    if witness then return 'witness', witness end

    if status.contact == 'soft' and status.track then
        return 'soft', status.track
    end

    local site = nearestUnhit(status)
    if site then return 'site', site end

    return nil
end

CreateThread(function()
    while true do
        Wait(1000)

        local role, status = NickState()

        if role ~= 'police' or not status.phase or status.phase == 'idle' then
            if route.blip then clearRoute() end
            leads = {}
        elseif not G.ENABLED then
            -- Nothing to do, and nothing to clean up but our own line.
            if route.blip then clearRoute() end
        else
            -- A hand-placed waypoint always wins. A copper who has decided
            -- where he is going does not want dispatch arguing with him, and
            -- the suppression outlives the waypoint so clearing it does not
            -- snap the line back the instant he lifts his finger.
            if IsWaypointActive() then
                manualUntil = GetGameTimer() + G.MANUAL_SUPPRESS_MS
                if route.blip then clearRoute() end
            elseif GetGameTimer() < manualUntil then
                if route.blip then clearRoute() end
            else
                local kind, at = pick(status)

                if not kind then
                    if route.blip then clearRoute() end
                else
                    local better = not route.kind
                        or PRIORITY[kind] < PRIORITY[route.kind]
                        or (GetGameTimer() - route.at) > G.HOLD_MS

                    if better and (kind ~= route.kind
                        or math.abs(at.x - route.x) > 15.0
                        or math.abs(at.y - route.y) > 15.0) then
                        clearRoute()

                        local blip = AddBlipForCoord(at.x, at.y, at.z)
                        SetBlipSprite(blip, 1)
                        SetBlipColour(blip, 3)
                        SetBlipScale(blip, 0.5)
                        SetBlipAsShortRange(blip, false)
                        BeginTextCommandSetBlipName('STRING')
                        AddTextComponentString('Dispatch')
                        EndTextCommandSetBlipName(blip)

                        SetBlipRoute(blip, true)
                        SetBlipRouteColour(blip, 3)

                        route = { blip = blip, kind = kind, at = GetGameTimer(), x = at.x, y = at.y }
                    elseif route.blip and DoesBlipExist(route.blip)
                        and (kind == route.kind) then
                        -- Same lead, moved a little (a live lock does this
                        -- constantly): follow it without rebuilding the route.
                        SetBlipCoords(route.blip, at.x, at.y, at.z)
                        route.x, route.y = at.x, at.y
                    end
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearRoute()
end)
