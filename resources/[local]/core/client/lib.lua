-- The shared client toolkit. Loaded INTO each mode's own script environment
-- via `client_script '@core/client/lib.lua'` in that mode's manifest - a
-- library, not an export, because half of these functions yield (Wait) and
-- FiveM exports cannot.
--
-- Before this existed, loadModel alone was copy-pasted into nine files, each
-- copy drifting its own way (three different timeouts, two different failure
-- behaviours). A mode should be its rules and its drama; the mechanics of
-- streaming a model or settling a ped onto solid ground are the same in every
-- one of them, and they live here exactly once.
--
-- Everything hangs off the single global `SBM` so nothing here can collide
-- with a mode's own locals.
SBM = SBM or {}

-- ===== models =====
-- Streams a model in and hands back the hash, or nil if the streamer never
-- delivered. Callers must handle nil: a missing model should degrade (skip the
-- car, keep the round) rather than error.
function SBM.loadModel(name, timeoutMs)
    local hash = GetHashKey(name)
    if not IsModelInCdimage(hash) then return nil end

    RequestModel(hash)

    local deadline = GetGameTimer() + (timeoutMs or 10000)
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end
        Wait(25)
    end

    return hash
end

-- ===== ground =====
-- Drops the player onto solid ground, waiting for the map to stream in first.
-- A single probe right after a teleport asks about terrain that hasn't loaded
-- yet, fails, and leaves you standing in the sky.
--
-- `expectedZ` is the height of the surface we meant to land on. The probe
-- starts 40m up and takes the FIRST surface going down, which next to a
-- building is its roof - the sanity check takes the intended height instead
-- and lets physics settle the rest.
function SBM.settleToGround(expectedZ)
    local ped = PlayerPedId()

    FreezeEntityPosition(ped, true)

    for _ = 1, 25 do
        local pos = GetEntityCoords(ped)
        RequestCollisionAtCoord(pos.x, pos.y, pos.z)

        Wait(100)

        if HasCollisionLoadedAroundEntity(ped) then
            local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 40.0, false)

            if found and expectedZ and groundZ > (expectedZ + 6.0) then
                found, groundZ = true, expectedZ
            end

            if found then
                SetEntityCoords(ped, pos.x, pos.y, groundZ + 1.0, false, false, false, false)
                break
            end
        end
    end

    FreezeEntityPosition(ped, false)
end

-- ===== HUD =====
function SBM.notify(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, true)
end

function SBM.drawText(text, x, y, scale, font)
    SetTextFont(font or 4)
    SetTextScale(scale or 0.5, scale or 0.5)
    SetTextColour(255, 255, 255, 225)
    SetTextOutline()
    SetTextCentre(true)

    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

-- The big centre-screen moment card. Fire and forget; it runs itself down.
function SBM.shard(title, subtitle)
    CreateThread(function()
        local movie = RequestScaleformMovie('MP_BIG_MESSAGE_FREEMODE')

        local deadline = GetGameTimer() + 5000
        while not HasScaleformMovieLoaded(movie) do
            if GetGameTimer() > deadline then return end
            Wait(0)
        end

        BeginScaleformMovieMethod(movie, 'SHOW_SHARD_WASTED_MP_MESSAGE')
        ScaleformMovieMethodAddParamPlayerNameString(title)
        ScaleformMovieMethodAddParamPlayerNameString(subtitle or '')
        EndScaleformMovieMethod()

        local showUntil = GetGameTimer() + 6000
        while GetGameTimer() < showUntil do
            DrawScaleformMovieFullscreen(movie, 255, 255, 255, 255, 0)
            Wait(0)
        end

        SetScaleformMovieAsNoLongerNeeded(movie)
    end)
end

-- ===== fades =====
-- Do something behind a black screen. The out is waited on so the work really
-- is hidden; the in is fired and left to run.
function SBM.behindFade(fn, outMs, inMs)
    DoScreenFadeOut(outMs or 600)
    Wait((outMs or 600) + 100)

    fn()

    DoScreenFadeIn(inMs or 800)
end

-- ===== zones =====
-- Is the player inside this circle? The bread and butter of Config.locations
-- zones - capture points, extraction circles, "get to the boat". Plain maths
-- rather than vector subtraction so it takes a vector3 OR a bare {x,y,z}
-- table straight out of a config.
function SBM.inRadius(coords, r)
    local at = GetEntityCoords(PlayerPedId())
    local dx, dy, dz = at.x - coords.x, at.y - coords.y, at.z - coords.z

    return (dx * dx + dy * dy + dz * dz) <= (r * r)
end

-- ===== entity bookkeeping =====
-- Every mode that spawns things needs the same two verbs: remember what I
-- made, and make it all go away. Each tracker is its own ledger, so a mode
-- can keep its fleet and its extras separate if it wants to.
function SBM.tracker()
    local entities = {}

    return {
        track = function(entity)
            if entity then entities[#entities + 1] = entity end
            return entity
        end,

        sweep = function()
            for _, entity in ipairs(entities) do
                if DoesEntityExist(entity) then
                    SetEntityAsMissionEntity(entity, true, true)
                    DeleteEntity(entity)
                end
            end
            entities = {}
        end,
    }
end

-- ===== peds that must not die by accident =====
-- Invincibility alone does not stop a fall: fall damage arrives as COLLISION
-- damage, the fourth proof, which is how an "invincible" AI could still be
-- killed by a drop off the hills.
function SBM.hardenPed(ped)
    SetEntityInvincible(ped, true)
    -- (bullet, fire, explosion, collision, melee, steam, p7, drown)
    SetEntityProofs(ped, true, true, true, true, true, true, true, true)
    SetPedSuffersCriticalHits(ped, false)
    SetPedDiesInWater(ped, false)
end
