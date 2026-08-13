-- core: who decides how busy Los Santos is.
--
-- The city is ALIVE by default. Nothing has to ask for that — it is simply what
-- you get in free roam, in the police chase, and in any mode written later that
-- never thinks about it. A mode that needs different streets makes a claim:
--
--     exports.core:setPopulation('empty')    -- the horde wants a ghost town
--     exports.core:setPopulation('sparse')   -- thinned out, but not dead
--     exports.core:clearPopulation()         -- done; give the city back
--
-- Claims are keyed by the resource that made them, so a mode can only ever
-- speak for itself, and they are released automatically when that resource
-- stops. A mode that crashes, gets stopped, or is hot-reloaded therefore can
-- never leave the streets permanently dead — the city comes back on its own.
--
-- If several modes claim at once the QUIETEST wins, so nothing can repopulate
-- a city another mode is deliberately emptying.

local RANK    = { empty = 0, sparse = 1, alive = 2 }
local DEFAULT = 'alive'

local claims  = {}       -- [resource name] = policy
local current = DEFAULT

local function resolve()
    local winner = DEFAULT

    for _, policy in pairs(claims) do
        if RANK[policy] < RANK[winner] then winner = policy end
    end

    return winner
end

-- Only talks to the network when the answer actually changes.
local function refresh()
    local next = resolve()
    if next == current then return end

    current = next
    TriggerClientEvent('core:population', -1, current)
    TriggerEvent('telemetry:mark', 'population:' .. current)
end

local function claimant()
    return GetInvokingResource() or GetCurrentResourceName()
end

local function setPopulation(policy)
    if not RANK[policy] then
        print(('[core] ignoring population claim from %s: unknown policy %q (want empty, sparse or alive)')
            :format(claimant(), tostring(policy)))
        return nil
    end

    claims[claimant()] = policy
    refresh()

    return current
end

local function clearPopulation()
    claims[claimant()] = nil
    refresh()

    return current
end

exports('setPopulation', setPopulation)
exports('clearPopulation', clearPopulation)

-- server/gametype.lua claims on a running mode's behalf. Shared as a global
-- because both files run in core, and a resource cannot call its own exports.
Population = { set = setPopulation, clear = clearPopulation }

exports('getPopulation', function()
    return current
end)

-- A mode letting go — deliberately or by falling over — hands the city back.
AddEventHandler('onResourceStop', function(resource)
    if claims[resource] == nil then return end

    claims[resource] = nil
    refresh()
end)

-- Clients ask on join AND every time their own core resource starts, which is
-- what makes hot-reloading core mid-round safe: they are told the real answer
-- instead of assuming the default.
RegisterNetEvent('core:worldReady', function()
    local source = source
    TriggerClientEvent('core:population', source, current)
end)

-- Console: why are the streets like this? Names who is holding the city down.
RegisterCommand('population', function()
    print(('[core] population is %s'):format(current))

    local held = false
    for resource, policy in pairs(claims) do
        held = true
        print(('[core]   %s claims %s'):format(resource, policy))
    end

    if not held then print('[core]   no claims - the city is its own') end
end, true)
