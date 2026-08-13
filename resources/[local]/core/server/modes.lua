-- Who owns the world. Exactly one place that knows how to clear the stage for
-- a mode and how to put the furniture back afterwards.
--
-- Before this, every mode carried its own copy of the stack: chase stopped
-- four resources by name to get a living city, put two of them back when it
-- finished, and telemetry's /resetgame had a third private list. Adding a mode
-- meant finding and editing every list. Now the stack is data, here.
--
-- Resource natives rather than console commands on purpose: a script has no
-- permission to run stop/ensure in the console and those calls were being
-- silently denied.

-- Everything that must be OFF for a mode to own the world outright: this
-- hardcoded legacy list, UNION whatever has registered with the gametype
-- framework (server/gametype.lua). A registered mode never needs to edit
-- this file - it lands on the stop-list by declaring itself.
local LEGACY_MODES = { 'infected_dev', 'pint', 'infected', 'squadmate', 'chase' }

local function allModes()
    local list, seen = {}, {}

    for _, name in ipairs(LEGACY_MODES) do
        seen[name] = true
        list[#list + 1] = name
    end

    -- GametypeResources lives in server/gametype.lua, which loads after this
    -- file - looked up at claim time, never at load time, so order is safe.
    for _, name in ipairs(GametypeResources and GametypeResources() or {}) do
        if not seen[name] then
            seen[name] = true
            list[#list + 1] = name
        end
    end

    return list
end

-- The default evening: what free roam runs when nobody has claimed the world.
-- Squadmates are deliberately absent (#18) - restoring the stack must not
-- quietly bring them back. Order matters: pint depends on infected being up.
local DEFAULT_STACK = { 'infected', 'pint' }

local claimedBy = nil

-- A mode calls this before it starts: everything else stops, the claimant is
-- left alone. Never yields, so it is safe as an export.
local function claimWorld(mode)
    claimedBy = mode

    for _, name in ipairs(allModes()) do
        if name ~= mode and GetResourceState(name) == 'started' then
            StopResource(name)
        end
    end

    print(('[core] world claimed by %s'):format(mode or '?'))
end

-- And this when it ends. The restart runs in its own thread because the stack
-- needs a beat between resources and exports cannot yield.
local function releaseWorld()
    claimedBy = nil

    CreateThread(function()
        for _, name in ipairs(DEFAULT_STACK) do
            if GetResourceState(name) ~= 'started' then
                StartResource(name)
                Wait(1000)
            end
        end

        print('[core] world handed back to the default stack')
    end)
end

exports('claimWorld', claimWorld)
exports('releaseWorld', releaseWorld)

-- server/gametype.lua claims on a mode's behalf. Shared as a global because
-- both files run in core, and a resource cannot call its own exports.
WorldClaim = { claim = claimWorld, release = releaseWorld }

exports('worldClaimedBy', function()
    return claimedBy
end)
