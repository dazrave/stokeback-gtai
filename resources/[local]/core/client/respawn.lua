-- The respawn service. One death-watcher for the whole server, with the
-- behaviour decided by whichever mode currently owns the player.
--
-- Before this, every mode wrote its own "am I dead yet" loop with its own
-- delay, its own fade, its own resurrect call and its own kit re-issue - and
-- every new mode would have written another. Now a mode states a POLICY and
-- the mechanics live here:
--
--   TriggerEvent('core:respawnPolicy', {
--       kind    = 'where-you-fell',  -- or 'off'
--       delay   = 5,                 -- seconds on the floor first
--       loadout = 'cop',             -- name from core/shared/loadouts.lua
--       downMessage = '~r~You are down.',
--       upMessage   = '~b~Back up.',
--   })
--
-- 'off' (the default) means the mode - or the base spawnmanager - handles
-- death itself. Modes with a bespoke flow (the horde's spectator system, the
-- campaign's checkpoints) simply never turn this on, and nothing fights them.
--
-- The policy resets itself to 'off' whenever a resource stops, so a mode that
-- dies mid-round can never leave its respawn rules haunting free roam.
local policy = { kind = 'off' }
local owner  = nil

-- RegisterNetEvent, not AddEventHandler: the gametype framework sends
-- policies from the SERVER (a descriptor's respawn block), and a handler
-- that isn't net-registered silently never hears a server event. A mode's
-- local TriggerEvent lands exactly as before. Server-sent policies have no
-- invoking resource, so no owner - the framework switches them off itself at
-- the end of the round.
RegisterNetEvent('core:respawnPolicy', function(next)
    if type(next) ~= 'table' or not next.kind then return end
    policy = next
    owner  = GetInvokingResource()
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == owner then
        policy = { kind = 'off' }
        owner  = nil
    end
end)

CreateThread(function()
    while true do
        Wait(500)

        if policy.kind == 'where-you-fell' then
            local ped = PlayerPedId()

            if IsEntityDead(ped) or IsPedFatallyInjured(ped) then
                if policy.downMessage then SBM.notify(policy.downMessage) end
                Wait((policy.delay or 5) * 1000)

                -- Check again: the mode may have ended (or switched its policy
                -- off) while we were counting - a death on the whistle must
                -- not haul somebody upright after the closing card has played.
                if policy.kind == 'where-you-fell' then
                    local at = GetEntityCoords(PlayerPedId())

                    DoScreenFadeOut(400)
                    Wait(500)

                    -- Up where you fell rather than back at base: a round out
                    -- in the sticks would otherwise end your evening anyway,
                    -- just with a very long drive attached.
                    NetworkResurrectLocalPlayer(at.x, at.y, at.z + 1.0,
                        GetEntityHeading(PlayerPedId()), true, false)

                    local up = PlayerPedId()
                    ClearPedTasksImmediately(up)
                    SetEntityHealth(up, GetEntityMaxHealth(up))
                    ClearPedBloodDamage(up)
                    SetPlayerInvincible(PlayerId(), false)

                    if policy.loadout then ApplyLoadout(policy.loadout) end

                    DoScreenFadeIn(600)
                    if policy.upMessage then SBM.notify(policy.upMessage) end
                end
            end
        end
    end
end)
