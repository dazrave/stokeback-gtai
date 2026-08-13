-- core: the round's clock and weather, claimed and put back like everything
-- else. Modes used to grab NetworkOverrideClockTime themselves and simply
-- never give it back - chase's golden hour followed everyone into free roam.
--
--     core:clock { hour = 22, minute = 0, weather = 'FOG', freeze = true }
--     core:clock            -- (nil) restore: override off, weather natural
--
-- freeze defaults to true, because pinning the light is why a mode sets a
-- clock at all. freeze = false keeps the hands moving from the given time:
-- the override native pins the clock, so a slow thread walks it forward at
-- the game's own pace (one game minute every two real seconds).
local spec  = nil
local hands = nil -- { hour, minute } advanced by the thread when unfrozen

local function apply(next)
    spec = next

    if not next then
        hands = nil
        -- The paired clear for NetworkOverrideClockTime. Named on current
        -- builds; invoked by hash if this client's natives table predates the
        -- name, because a missing global would kill the restore outright.
        if NetworkClearClockTimeOverride then
            NetworkClearClockTimeOverride()
        else
            Citizen.InvokeNative(0xD972DF67326F966E)
        end
        ClearWeatherTypePersist()
        return
    end

    hands = { hour = next.hour or 12, minute = next.minute or 0 }
    NetworkOverrideClockTime(hands.hour, hands.minute, 0)

    if next.weather then
        SetWeatherTypeNowPersist(next.weather)
    end
end

RegisterNetEvent('core:clock', function(next)
    if next ~= nil and type(next) ~= 'table' then return end
    apply(next)
end)

CreateThread(function()
    while true do
        Wait(2000)

        if spec and spec.freeze == false and hands then
            hands = {
                hour   = (hands.hour + math.floor((hands.minute + 1) / 60)) % 24,
                minute = (hands.minute + 1) % 60,
            }
            NetworkOverrideClockTime(hands.hour, hands.minute, 0)
        end
    end
end)

-- Core going down mid-round must not leave the sky stuck at golden hour.
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and spec then apply(nil) end
end)
