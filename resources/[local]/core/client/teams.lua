-- core: the client half of teams, and the friendly-fire referee.
--
-- Two jobs. One: remember which side I am on and stamp it onto my ped as a
-- synced DECOR, because relationship groups do not sync between clients (the
-- oldest gotcha in AGENTS.md) - a decor is the only team badge a neighbour's
-- machine can actually read. Two: enforce the running gametype's friendly-
-- fire policy, which before this was a per-tick tug-of-war between modes.
--
-- 'auto' means cross-team only, assembled locally on EVERY machine from the
-- same synced decors, so no machine has to be told anything: player damage is
-- switched on globally, then each client sorts the player peds it can see
-- into two local relationship groups - my team alongside me, everyone else
-- apart - and SetCanAttackFriendly(me, false) refuses the same-group hits.
-- All machines read the same decors, so they all reach the same answer.
DecorRegister('SBM_TEAM', 3) -- 3 = int; idempotent across resources

AddRelationshipGroup('SBM_TEAMMATES')
AddRelationshipGroup('SBM_RIVALS')

-- A group's hash is just the joaat of its name, which sidesteps the native's
-- awkward return convention.
local PLAYER_GROUP = GetHashKey('PLAYER')
local TEAMMATES    = GetHashKey('SBM_TEAMMATES')
local RIVALS       = GetHashKey('SBM_RIVALS')

-- Rivals are explicitly NEUTRAL (3), never friendly: anything warmer and
-- SetCanAttackFriendly would swallow cross-team damage too, which is the
-- whole round in chase.
SetRelationshipBetweenGroups(3, TEAMMATES, RIVALS)
SetRelationshipBetweenGroups(3, RIVALS, TEAMMATES)

local round       = nil   -- { name, label, ff } while a framework round runs
local myTeam      = nil   -- { id, label, colour, loadout, int }
local partitioned = false -- have we moved peds out of the default PLAYER group?

local function refresh()
    if not round then return end

    local me = PlayerPedId()
    local ff = round.ff

    -- Re-stamped every pass on purpose, whatever the FF policy:
    -- SetPlayerModel and a respawn both hand you a brand new ped with no
    -- decor, and the badge is what every other machine reads teams from.
    if myTeam and myTeam.int then
        DecorSetInt(me, 'SBM_TEAM', myTeam.int)
    end

    if ff == true then
        -- Everyone can hurt everyone; no sorting needed.
        NetworkSetFriendlyFireOption(true)
        SetCanAttackFriendly(me, true, true)
        return
    end

    if ff ~= 'auto' then
        -- false (or unset): mates cannot shoot each other, full stop - the
        -- same pair of calls the zombie modes always forced.
        NetworkSetFriendlyFireOption(false)
        SetCanAttackFriendly(me, false, false)
        return
    end

    -- 'auto': cross-team only.
    NetworkSetFriendlyFireOption(true)
    SetCanAttackFriendly(me, false, false)

    if not (myTeam and myTeam.int) then return end

    SetPedRelationshipGroupHash(me, TEAMMATES)
    partitioned = true

    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= PlayerId() then
            local ped = GetPlayerPed(pid)
            if DoesEntityExist(ped) then
                local theirs = DecorExistOn(ped, 'SBM_TEAM') and DecorGetInt(ped, 'SBM_TEAM') or 0
                SetPedRelationshipGroupHash(ped,
                    (theirs ~= 0 and theirs == myTeam.int) and TEAMMATES or RIVALS)
            end
        end
    end
end

local function restoreAll()
    NetworkSetFriendlyFireOption(false)

    local me = PlayerPedId()
    SetCanAttackFriendly(me, false, false)
    DecorSetInt(me, 'SBM_TEAM', 0)

    if partitioned then
        SetPedRelationshipGroupHash(me, PLAYER_GROUP)
        for _, pid in ipairs(GetActivePlayers()) do
            local ped = GetPlayerPed(pid)
            if DoesEntityExist(ped) then SetPedRelationshipGroupHash(ped, PLAYER_GROUP) end
        end
        partitioned = false
    end

    myTeam = nil
end

-- The server says which side I'm on (broadcast for every player; only my own
-- line matters here). A per-team kit is applied on the spot, same as any
-- other loadout.
RegisterNetEvent('core:teamChanged', function(src, _, def)
    if src ~= GetPlayerServerId(PlayerId()) then return end

    myTeam = def or nil

    if myTeam then
        DecorSetInt(PlayerPedId(), 'SBM_TEAM', myTeam.int or 0)
        if myTeam.loadout then ApplyLoadout(myTeam.loadout) end
        refresh() -- sides changed: re-sort now, not in two seconds
    else
        DecorSetInt(PlayerPedId(), 'SBM_TEAM', 0)
    end
end)

-- The framework raising and striking the round. nil = round over: friendly
-- fire back to the FiveM default (off) and every ped back in its own group.
RegisterNetEvent('core:gametype', function(info)
    round = type(info) == 'table' and info or nil

    if round then refresh() else restoreAll() end
end)

CreateThread(function()
    while true do
        Wait(2000)
        if round then refresh() end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and round then
        round = nil
        restoreAll()
    end
end)
