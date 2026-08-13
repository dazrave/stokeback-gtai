-- Objective line, fuel gauge, holdout clock and the big shard messages.
PintHUD = {}

local state = {
    objective = nil, distance = nil, fuel = nil, refuelling = false,
    holdout = nil, gather = nil, regroup = nil, missionName = nil,
    secure = nil, secureHeld = false, secureWaves = nil,
}

-- Merge-set. Pass '__clear' to null a field out (plain nil would just be
-- skipped by pairs()).
function PintHUD.set(next)
    local merged = {}
    for key, value in pairs(state) do merged[key] = value end
    for key, value in pairs(next) do
        if value == '__clear' then
            merged[key] = nil
        else
            merged[key] = value
        end
    end
    state = merged
end

local function drawText(text, x, y, scale)
    SetTextFont(4)
    SetTextScale(scale or Config.hud.scale, scale or Config.hud.scale)
    SetTextColour(255, 255, 255, 220)
    SetTextOutline()

    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function fuelColour(fuel)
    if fuel > 50 then return '~g~' end
    if fuel > 20 then return '~y~' end
    return '~r~'
end

CreateThread(function()
    while true do
        -- Mission title, small and grey above the objective - the single-player
        -- "you are in a mission" anchor.
        if state.missionName then
            drawText('~c~' .. state.missionName, Config.hud.objX, Config.hud.objY - 0.033, 0.38)
        end

        if state.objective then
            local line = '~y~' .. state.objective

            if state.holdout then
                line = ('~y~%s ~w~- %d:%02d'):format(
                    state.objective, math.floor(state.holdout / 60), state.holdout % 60)
            elseif state.distance then
                line = ('~y~%s ~w~- %s'):format(state.objective, state.distance)
            end

            if state.secure then
                -- Waves first: putting the horde down IS the objective now.
                -- The floor seconds only surface once every wave is cleared.
                local gate = state.secureWaves
                    and ('CLEAR THE WAVES %s'):format(state.secureWaves)
                    or ('SECURE THE AREA %ds'):format(state.secure)
                line = ('~y~%s ~w~- ~r~%s%s'):format(
                    state.objective, gate, state.secureHeld and ' ~o~(HELD)' or '')
            end

            if state.gather then
                line = line .. ('  ~g~[%s loaded]'):format(state.gather)
            end
            if state.regroup then
                line = line .. ('  ~b~[%s there]'):format(state.regroup)
            end

            drawText(line, Config.hud.objX, Config.hud.objY)
        end

        if state.fuel then
            local text = state.refuelling
                and ('~b~REFUELLING %d%%'):format(state.fuel)
                or ('FUEL %s%d%%'):format(fuelColour(state.fuel), state.fuel)

            drawText(text, Config.hud.fuelX, Config.hud.fuelY)
        end

        Wait(0)
    end
end)

PintHUD.notify = SBM.notify

-- The big cinematic banner (GTA's "shard") for mission start and the win.
PintHUD.shard = SBM.shard
