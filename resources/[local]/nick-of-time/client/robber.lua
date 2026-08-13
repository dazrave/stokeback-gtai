-- The robber's brain: the bag, the two ways into a shop, the dive, and the
-- getaway car's slow public death.
--
-- Everything expensive runs on HIS machine on purpose - it owns his ped, so
-- nothing anybody else does can put him under the health floor, and the police
-- never receive a single number that could be read as his position.
local memo = {
    lastVehicle = 0,
    bodyHealth  = nil,
    hits        = 0,
    onFire      = false,
    nextStutter = 0,
    coughs      = 0,   -- which of her lines she is on
    hidden      = false,
    asked       = false, -- a vanish request is in flight; wait for the verdict
    inHouse     = 0,   -- game time we entered a safehouse zone
    callHold    = 0,   -- game time G went down at a safehouse door
    pressure    = 0,
    pressureAt  = 0,
    blips       = {},
}

local function isRobber()
    local role, status = NickState()
    return role == 'robber' and status.phase == 'active'
end

-- Read by patrol.lua: a client in the safehouse bucket creates entities in
-- the safehouse bucket, so nothing may be spawned while this is true - a
-- patrol car nobody can see is not pressure, it is a haunting.
function NickVanished()
    return memo.hidden
end

local function nearest(list, radius)
    if not list then return nil end

    local me = GetEntityCoords(PlayerPedId())
    local bestIndex, bestGap = nil, nil

    for index, place in ipairs(list) do
        local gap = #(vector3(place.x, place.y, place.z) - me)
        if gap <= radius and (not bestGap or gap < bestGap) then
            bestIndex, bestGap = index, gap
        end
    end

    return bestIndex
end

local function help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

-- ===== his map =====
-- He sees the shops AND this round's safehouses; the police only ever get the
-- shops. Drawn here rather than in main.lua so the two roles can never
-- accidentally share a blip list.
local function clearBlips()
    for _, blip in ipairs(memo.blips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    memo.blips = {}
end

CreateThread(function()
    while true do
        Wait(1000)

        local role, status = NickState()

        if role == 'robber' and status.phase and status.phase ~= 'idle' then
            if #memo.blips == 0 then
                local map = NickMap()

                for _, site in ipairs(map.sites or {}) do
                    local blip = AddBlipForCoord(site.x, site.y, site.z)
                    SetBlipSprite(blip, 1)
                    SetBlipColour(blip, 5)
                    SetBlipScale(blip, 0.7)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentString(site.name or 'Shop')
                    EndTextCommandSetBlipName(blip)
                    memo.blips[#memo.blips + 1] = blip
                end

                for _, house in ipairs(map.houses or {}) do
                    local blip = AddBlipForCoord(house.x, house.y, house.z)
                    SetBlipSprite(blip, 1)
                    SetBlipColour(blip, 2) -- green: the only number that scores
                    SetBlipScale(blip, 0.8)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentString(house.name or 'Safehouse')
                    EndTextCommandSetBlipName(blip)
                    memo.blips[#memo.blips + 1] = blip
                end
            end
        elseif #memo.blips > 0 then
            clearBlips()
        end
    end
end)

-- (There used to be a position heartbeat here. The server reads his position
-- off its own copy of the ped now - an event carrying coords was the one
-- thing a modded client could lie about, and everything worth stealing
-- measured against it.)

-- ===== the two ways in, and the way out =====
CreateThread(function()
    while true do
        Wait(0)

        if not isRobber() then
            Wait(300)
        else
            local map   = NickMap()
            local purse = NickPurse()
            local ped   = PlayerPedId()
            local onFoot = not IsPedInAnyVehicle(ped, false)

            local site  = onFoot and nearest(map.sites, Config.looting.ZONE_RADIUS) or nil
            local holdingCallIt = false
            -- The safehouse zone works from behind the wheel too, but only for
            -- one thing: driving a nicked exotic through the door is the whole
            -- of cars-as-loot. Stashing, diving and calling it a day all still
            -- mean getting out.
            local house = nearest(map.houses, Config.safehouses.ZONE_RADIUS)

            if not onFoot and house and purse.car then
                help(('~INPUT_PICKUP~ Cash in the %s ~w~- %s (%d%% of her left)'):format(
                    purse.car.model or 'car', NickHUD.money(purse.car.value), math.floor(purse.car.pct * 100)))

                if IsControlJustReleased(0, Config.controls.PRIMARY) then
                    TriggerServerEvent('nick:cashCar')
                end

            elseif not onFoot then
                -- Behind the wheel and not at a safehouse: no prompts at all.

            elseif purse.job then
                -- Already at it. The only decision left is when to leave, and
                -- the alarm state is the only hint he gets about that.
                help(purse.job.alarmed
                    and '~r~ALARM GOING~w~ - walk out of the zone whenever you like'
                    or  'Filling the bag. Walk out of the zone to stop.')

            elseif site then
                help('~INPUT_PICKUP~ Quiet entry ~w~(full till, alarm on a timer you cannot see)  ~n~'
                    .. '~INPUT_DETONATE~ Smash and grab ~w~(faster, smaller, alarm now)')

                if IsControlJustReleased(0, Config.controls.PRIMARY) then
                    TriggerServerEvent('nick:job', site, 'quiet')
                elseif IsControlJustReleased(0, Config.controls.SECONDARY) then
                    TriggerServerEvent('nick:job', site, 'smash')
                end

            elseif house then
                local carried = purse.carried or 0
                local walks   = carried + (purse.stashed or 0)

                -- Ending the round is a HOLD, never a tap. G is also the
                -- smash-and-grab key - a key a robber has been spamming at
                -- shop windows all round must not end his evening on one
                -- loose press (Rory, night one of the default map: one G at
                -- a door, round over, £6,428 still in the bag). The bag
                -- banks on the way out (the server's side of the same fix),
                -- so the prompt can promise the whole total.
                if IsControlPressed(0, Config.controls.SECONDARY) then
                    holdingCallIt = true
                    if memo.callHold == 0 then memo.callHold = GetGameTimer() end

                    if GetGameTimer() - memo.callHold >= Config.safehouses.CALLIT_HOLD_MS then
                        memo.callHold = 0
                        TriggerServerEvent('nick:callItADay')
                    else
                        help(('~INPUT_DETONATE~ Keep holding to call it a day ~w~- walks with %s')
                            :format(NickHUD.money(walks)))
                    end
                else
                    help(('~INPUT_PICKUP~ Stash %s  ~n~~INPUT_DETONATE~ Hold: call it a day ~w~(ends the round, banks the bag, walks with %s)')
                        :format(NickHUD.money(carried), NickHUD.money(walks)))

                    if IsControlJustReleased(0, Config.controls.PRIMARY) then
                        TriggerServerEvent('nick:stash', house)
                    end
                end
            end

            -- The hold survives only unbroken pressure at the door: step out
            -- of the zone, get in a car, or let go and the clock starts over.
            if not holdingCallIt then memo.callHold = 0 end
        end
    end
end)

-- ===== the dive =====
-- Round a corner, through a doorway, gone. A routing bucket is the only thing
-- that makes him genuinely invisible rather than merely hard to see - the
-- entire force can drive through the doorway and never know - and it is
-- granted by the server, so this only ever ASKS.
--
-- The clear window is the whole point, and the SERVER referees it: it holds
-- the only truthful copy of "is anyone looking". Stand in the zone for the
-- window, ask, and either vanish (nick:hidden) or get the loud SPOTTED
-- (nick:spotted) and have to lose them first. This client used to judge the
-- window itself off a broadcast contact state - which meant the police
-- picture had to be sent to the robber's machine, and acceptance test 9
-- frowns on handing the fox the hunt's map.
CreateThread(function()
    while true do
        Wait(200)

        local role, status = NickState()

        if role ~= 'robber' or status.phase ~= 'active' then
            if memo.hidden then
                memo.hidden = false
                TriggerServerEvent('nick:vanish', false)
            end
            memo.inHouse, memo.asked = 0, false
        else
            local ped   = PlayerPedId()
            local house = not IsPedInAnyVehicle(ped, false)
                and nearest(NickMap().houses, Config.safehouses.ZONE_RADIUS) or nil

            if house then
                if memo.inHouse == 0 then memo.inHouse = GetGameTimer() end

                if not memo.hidden and not memo.asked
                    and GetGameTimer() - memo.inHouse >= Config.safehouses.SAFEHOUSE_ENTRY_CLEAR_MS then
                    memo.asked = true
                    TriggerServerEvent('nick:vanish', true)
                end
            else
                memo.inHouse, memo.asked = 0, false

                if memo.hidden then
                    memo.hidden = false
                    TriggerServerEvent('nick:vanish', false)
                    NickHUD.notify('~y~Back out on the pavement.')
                end
            end
        end
    end
end)

-- The verdicts. Granted: he is in the safehouse bucket and off every screen.
RegisterNetEvent('nick:hidden', function()
    if not isRobber() then return end

    memo.hidden = true
    memo.asked  = false
    NickHUD.notify('~g~You are off the street.~w~ Let them drive past.')
end)

-- Refused: somebody watched him walk in, so nothing happened except the
-- doorway getting warmer. The window restarts - lose them, then try again.
RegisterNetEvent('nick:spotted', function()
    if not isRobber() then return end

    memo.asked   = false
    memo.inHouse = GetGameTimer()
    NickHUD.notify('~r~SPOTTED.~w~ They watched you walk in. Lose them first.')
end)

-- ===== hauled out of the car =====
-- The other half of "jack, never enter". The copper who pressed the button
-- gets an animation; the actual leaving happens HERE, on the machine that owns
-- this ped, because a task issued on somebody else's ped is a suggestion at
-- best and a desync at worst.
RegisterNetEvent('nick:jacked', function()
    local role, status = NickState()
    if role ~= 'robber' or status.phase ~= 'active' then return end

    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return end

    NickHUD.notify('~r~THEY HAVE GOT THE DOOR OPEN.')
    NickAnim(Config.jack.ANIM_DICT, Config.jack.ANIM_ROBBER, Config.jack.ANIM_MS)

    TaskLeaveVehicle(ped, vehicle, Config.jack.LEAVE_FLAGS)
    SetPedToRagdoll(ped, Config.jack.RAGDOLL_MS, Config.jack.RAGDOLL_MS, 0, true, true, false)
end)

-- ===== pressure =====
-- He never sees the police on his map. He gets a feeling, and a late one:
-- three states, delayed by PRESSURE_UPDATE_DELAY_MS, so he is always reacting
-- to something that was true a moment ago.
local PRESSURE_LINES = { '~g~QUIET', '~y~SOMEONE IS CLOSE', '~r~THEY ARE ON TOP OF YOU' }

CreateThread(function()
    while true do
        Wait(500)

        local role, status = NickState()

        if role == 'robber' and status.phase == 'active' then
            if GetGameTimer() >= memo.pressureAt then
                memo.pressureAt = GetGameTimer() + Config.pressure.PRESSURE_UPDATE_DELAY_MS

                local P     = Config.pressure
                local me    = GetEntityCoords(PlayerPedId())
                local close = 0

                for _, id in ipairs(GetActivePlayers()) do
                    if id ~= PlayerId() then
                        local ped = GetPlayerPed(id)
                        if DoesEntityExist(ped)
                            and #(GetEntityCoords(ped) - me) < P.PRESSURE_RADIUS then
                            close = close + 1
                        end
                    end
                end

                -- The AI half, capped hard. At five stars the bar must still
                -- have somewhere to go when a HUMAN comes round the corner -
                -- a meter pegged by patrols would cost him the one warning
                -- that actually matters. A third of the bar, and not a pixel
                -- more, however many of them are out there.
                local ceiling = (P.PRESSURE_STATES - 1) * P.PRESSURE_AI_CONTRIBUTION
                local ai      = math.min(NickPatrolCount(P.PRESSURE_RADIUS) * P.PRESSURE_AI_CONTRIBUTION, ceiling)

                -- Rounded, not floored. The AI term is always under one whole
                -- state (the cap is a third of a two-step bar), so a floor
                -- threw it away entirely and the patrols never moved the
                -- needle at all. Rounding lets a pair of them register as
                -- SOMEONE IS CLOSE while the top of the bar still needs an
                -- actual human in it.
                memo.pressure = math.min(P.PRESSURE_STATES - 1, math.floor(close + ai + 0.5))
            end
        else
            memo.pressure = 0
        end
    end
end)

CreateThread(function()
    while true do
        Wait(0)

        local role, status = NickState()

        if role == 'robber' and status.phase == 'active' then
            -- Third line down: the clock is first, "IF YOU BANK" is second
            -- (main.lua), and the feeling is last.
            NickHUD.draw(PRESSURE_LINES[memo.pressure + 1] or PRESSURE_LINES[1],
                Config.hud.x, Config.hud.y + 0.064, Config.hud.scale * 0.85)
        else
            Wait(400)
        end
    end
end)

-- ===== witnesses =====
-- Plan §3.4. A crash only gets phoned in if somebody was actually there to see
-- it: empty docks at 3am, silence; Vespucci Beach at dusk, instant call. This
-- is the entire reason the mode leaves the city populated instead of emptying
-- it - the NPCs are not scenery, they are the intelligence network.
--
-- Deliberately cheap: only peds already inside the radius get a raycast, and
-- only up to MAX_CHECKED of them, because this fires in the same frame as a
-- crash and a crash is the worst possible moment to drop twenty milliseconds.
local witnessAt = 0

-- `loud` waives the line-of-sight half: a big crash or gunfire is HEARD, and
-- a wall between the witness and the noise does not stop the phone call. The
-- NPC still has to exist and be in radius - the empty docks stay silent,
-- which is the entire point of witness-modelling the calls.
function NickWitness(kind, loud)
    if not Config.witness.ENABLED then return end
    if GetGameTimer() < witnessAt then return end

    local ped     = PlayerPedId()
    local me      = GetEntityCoords(ped)
    local checked = 0
    local seen    = false

    for _, other in ipairs(GetGamePool('CPed')) do
        if checked >= Config.witness.MAX_CHECKED then break end

        if DoesEntityExist(other) and other ~= ped
            and not IsPedAPlayer(other) and not IsEntityDead(other)
            and #(GetEntityCoords(other) - me) < Config.witness.RADIUS then
            checked = checked + 1

            if loud or HasEntityClearLosToEntity(other, ped, Config.detection.LOS_FLAGS) then
                seen = true
                break
            end
        end
    end

    if not seen then return end

    -- The gap is held here as well as on the server: a bad driver in a busy
    -- street would otherwise be a live tracker with extra steps.
    witnessAt = GetGameTimer() + Config.witness.GAP_S * 1000
    TriggerServerEvent('nick:witness', kind)
end

-- Gunshots near him get phoned in (heard, never sighted - the 999 still
-- reports a point, and the server still uses ITS read of where he is). A
-- copper has to already be within GUNFIRE_RADIUS of him to set one off, so it
-- cannot be fished for from across the map - but a warning shot to wake the
-- neighbourhood up is legitimate policing, and honestly quite funny.
CreateThread(function()
    while true do
        Wait(300)

        if isRobber() and Config.witness.GUNFIRE then
            local me = GetEntityCoords(PlayerPedId())

            for _, id in ipairs(GetActivePlayers()) do
                if id ~= PlayerId() then
                    local shooter = GetPlayerPed(id)

                    if DoesEntityExist(shooter) and IsPedShooting(shooter)
                        and #(GetEntityCoords(shooter) - me) < Config.witness.GUNFIRE_RADIUS then
                        NickWitness('gunfire', true)
                        break
                    end
                end
            end
        else
            Wait(700)
        end
    end
end)

-- The piloted heli's proximity icon (the scope's own fair-warning trade): a
-- police helicopter inside HELI_PROXIMITY_ICON_RADIUS shows on the ROBBER'S
-- map. He is the only one who gets it - it is the counterweight to 250m
-- eyes, not a gift to the force - and it tracks the machine, so ducking
-- under cover while the icon slides past is a real play.
CreateThread(function()
    local blip = nil

    while true do
        Wait(2000)

        local near = nil

        if isRobber() then
            local me = GetEntityCoords(PlayerPedId())

            for _, id in ipairs(GetActivePlayers()) do
                if id ~= PlayerId() then
                    local ped = GetPlayerPed(id)
                    local veh = DoesEntityExist(ped) and GetVehiclePedIsIn(ped, false) or 0

                    if veh ~= 0 and IsThisModelAHeli(GetEntityModel(veh))
                        and #(GetEntityCoords(veh) - me) < Config.detection.HELI_PROXIMITY_ICON_RADIUS then
                        near = veh
                        break
                    end
                end
            end
        end

        if near and not (blip and DoesBlipExist(blip)) then
            blip = AddBlipForEntity(near)
            SetBlipSprite(blip, 64) -- the helicopter glyph
            SetBlipColour(blip, 1)
            SetBlipScale(blip, 0.9)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString('Helicopter')
            EndTextCommandSetBlipName(blip)
        elseif not near and blip then
            if DoesBlipExist(blip) then RemoveBlip(blip) end
            blip = nil
        end
    end
end)

-- ===== the getaway car's slow public death =====
-- She coughs, she catches, and then she puts him across a pavement in front of
-- three squad cars. Damage is counted the way chase counts it: only another
-- VEHICLE can set the damaged-by-a-vehicle bit (walls and kerbs are map
-- collision, a lamppost is an object), and the threshold throws away the
-- traffic scrapes so only deliberate shunts count.
CreateThread(function()
    while true do
        Wait(500)

        if not isRobber() then
            memo.lastVehicle, memo.hits, memo.onFire, memo.dead = 0, 0, false, false
        else
            local ped     = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                if vehicle ~= memo.lastVehicle then
                    local firstCar = memo.lastVehicle == 0

                    -- A fresh car is a fresh set of chances, and a fresh voice.
                    memo.lastVehicle = vehicle
                    memo.bodyHealth  = GetVehicleBodyHealth(vehicle)
                    memo.hits        = 0
                    memo.onFire      = false
                    memo.dead        = false
                    memo.coughs      = 0
                    ClearEntityLastDamageEntity(vehicle)

                    -- A witnessed event, and the one the plan calls out by
                    -- name (§4.3, open question 4): changing cars in front of
                    -- people is how the police find out you changed cars.
                    -- Except the round's FIRST car, which is the one the mode
                    -- handed him at spawn: nobody phones in a man getting
                    -- into his own motor, and a 999 pin on the spawn in the
                    -- opening seconds would hand the police the one thing
                    -- the muster points were placed not to know.
                    if not firstCar then NickWitness('swap') end
                end

                local body   = GetVehicleBodyHealth(vehicle)
                local drop   = memo.bodyHealth and (memo.bodyHealth - body) or 0.0
                local engine = GetVehicleEngineHealth(vehicle) / 1000.0

                if HasEntityBeenDamagedByAnyVehicle(vehicle)
                    and drop >= Config.damage.MIN_RAM_DAMAGE then
                    memo.hits = memo.hits + 1
                    ClearEntityLastDamageEntity(vehicle)

                    -- A counted shunt costs ENGINE as well as panels. GTA puts
                    -- collision damage almost entirely into bodywork, so a car
                    -- rammed all round the block still pulled like new and the
                    -- ladder's stutter and STOP never fired - night one's
                    -- "there's no car health?". This is what makes ramming
                    -- actually work as the strategy the plan says it is.
                    local cost = Config.damage.RAM_ENGINE_COST or 0
                    if cost > 0 and not memo.dead then
                        SetVehicleEngineHealth(vehicle,
                            math.max(0.0, GetVehicleEngineHealth(vehicle) - cost))
                    end
                end

                -- His own driving counts as damage AND as an incident: put it
                -- into a bus stop in front of people and somebody phones it in.
                -- A really big one is HEARD (no line of sight needed): a car
                -- folding itself round a lamppost is not a subtle noise.
                if drop >= Config.witness.CRASH_DAMAGE then
                    NickWitness('crash', drop >= (Config.witness.LOUD_CRASH_DAMAGE or math.huge))
                end

                memo.bodyHealth = body

                -- On her last legs: the engine cuts out in little bursts, so
                -- every junction becomes a question. Her commentary escalates
                -- through Config.damage.COUGH_LINES in order and loops. Not
                -- once she is DEAD, though - a corpse does not cough, and the
                -- stutter's restart half was quietly turning a dead engine
                -- back on every couple of seconds.
                if engine <= Config.damage.DAMAGE_STUTTER_THRESHOLD
                    and not memo.dead and not memo.onFire
                    and GetGameTimer() >= memo.nextStutter then
                    memo.nextStutter = GetGameTimer() + Config.damage.STUTTER_EVERY_MS

                    local lines = Config.damage.COUGH_LINES
                    if lines and #lines > 0 then
                        memo.coughs = memo.coughs + 1
                        NickHUD.notify('~y~' .. lines[1 + ((memo.coughs - 1) % #lines)])
                    end

                    local band = Config.damage.DAMAGE_STUTTER_MS
                    SetVehicleEngineOn(vehicle, false, true, true)
                    Wait(math.random(band[1], band[2]))
                    SetVehicleEngineOn(vehicle, true, true, false)
                end

                -- The rung the ladder was missing: she STOPS. At the bottom of
                -- the engine she cuts out for good and he is on foot whether
                -- he likes it or not - which is what makes the pull-out and
                -- the foot chase reachable without anyone having to set fire
                -- to anything.
                if not memo.dead and engine <= Config.damage.DEAD_ENGINE_THRESHOLD then
                    memo.dead = true
                    memo.hits = 0 -- the fire count starts from the moment she died

                    SetVehicleUndriveable(vehicle, true)
                    SetVehicleEngineHealth(vehicle, 0.0)
                    NickHUD.shard('SHE\'S DEAD', 'That is as far as she goes. Run.')
                end

                -- Enough punishment while she is already dead and she goes up.
                if not memo.onFire and memo.dead
                    and memo.hits >= Config.damage.DAMAGE_HITS_TO_FIRE then
                    memo.onFire = true

                    NickHUD.shard('SHE\'S GOING UP', 'Out. Now. Run.')
                    StartEntityFire(vehicle)
                    TaskLeaveVehicle(ped, vehicle, 4160) -- bail at speed: that is the joke

                    local doomed = vehicle
                    CreateThread(function()
                        Wait(Config.damage.FIRE_TO_EXPLOSION_MS)
                        if DoesEntityExist(doomed) then
                            NetworkExplodeVehicle(doomed, true, false, false)
                        end
                    end)
                end
            end
        end
    end
end)

-- ===== no guns, endless legs =====
CreateThread(function()
    while true do
        Wait(2000)

        local role, status = NickState()

        if role == 'robber' and status.phase and status.phase ~= 'idle' then
            local ped = PlayerPedId()
            RemoveAllPedWeapons(ped, true)

            -- The foot chase should end in a tackle, not in him wheezing to a
            -- halt at the end of an alley.
            if Config.pressure.ROBBER_INFINITE_STAMINA then
                RestorePlayerStamina(PlayerId(), 1.0)
            end

            -- (bullet, fire, EXPLOSION, collision, melee, steam, p7, drown).
            -- The fireball has to throw him across the pavement without
            -- killing him: it is the safety requirement and the joke in the
            -- same native. The push is physics, so he still goes flying.
            if Config.damage.ROBBER_EXPLOSION_PROOF then
                SetEntityProofs(ped, false, false, true, false, false, false, false, false)
            end

            -- Guns become tyre tools by construction (plan §5.2): nobody ends
            -- a pursuit by shooting the driver through the rear windscreen.
            -- Re-asserted rather than set once - it resets with the ped.
            SetPedCanBeShotInVehicle(ped, Config.damage.ROBBER_SHOT_IN_VEHICLE and true or false)
        end
    end
end)

-- ===== non-lethal by law =====
-- Straight out of chase, and for the same reason: the round has exactly three
-- endings and none of them is "shot dead in a car park". He takes the hit, he
-- limps, he goes down long enough to be cuffed - he never dies.
CreateThread(function()
    local wasHit, nextKnockdown = false, 0
    local stungun = GetHashKey(Config.kit.TASER_WEAPON)

    while true do
        Wait(0)

        local role, status = NickState()

        if role == 'robber' and status.phase and status.phase ~= 'idle'
            and Config.nonLethal.enabled then
            local ped    = PlayerPedId()
            local health = GetEntityHealth(ped)

            -- The taser, the scope's intended foot-chase ender. GTA's own
            -- stun ragdoll on a player is over in a blink; a hit extends
            -- into the same knockdown window the gunfire floor uses, on the
            -- same rate limit, so he cannot be chain-tased into a nap. The
            -- damage flag latches, so it is cleared even when the rate limit
            -- swallows the hit - a stale one must not fire seconds later.
            if HasPedBeenDamagedByWeapon(ped, stungun, 0) then
                ClearPedLastWeaponDamage(ped)

                local knock = Config.nonLethal.knockdown
                if knock.enabled and not IsPedInAnyVehicle(ped, false)
                    and GetGameTimer() >= nextKnockdown then
                    nextKnockdown = GetGameTimer() + knock.everyMs
                    SetPedToRagdoll(ped, knock.downMs, knock.downMs, 0, true, true, false)
                    NickHUD.notify('~r~TASED.~w~ Everything is pins and needles.')
                end
            end

            if not IsEntityDead(ped) and health < Config.nonLethal.floorHealth then
                SetEntityHealth(ped, Config.nonLethal.floorHealth)

                if not wasHit then
                    wasHit = true
                    NickHUD.notify('~r~You\'re hit.~w~ Still standing. Move.')
                    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.4)
                end

                local knock = Config.nonLethal.knockdown
                if knock.enabled and not IsPedInAnyVehicle(ped, false)
                    and GetGameTimer() >= nextKnockdown then
                    nextKnockdown = GetGameTimer() + knock.everyMs
                    SetPedToRagdoll(ped, knock.downMs, knock.downMs, 0, true, true, false)
                    NickHUD.notify('~r~DOWN.~w~ Get up before they reach you.')
                end
            elseif health > Config.nonLethal.limpBelow then
                wasHit = false
            end

            SetPedMoveRateOverride(ped, health <= Config.nonLethal.limpBelow and 0.85 or 1.0)
        else
            Wait(500)
        end
    end
end)

-- They called the favour in. He is told, loudly, because a helicopter is the
-- least subtle object in Los Santos and pretending otherwise would be worse
-- than telling him - and because twenty seconds of knowing you are lit up is
-- the best twenty seconds in the round.
RegisterNetEvent('nick:heliOverhead', function()
    local role, status = NickState()
    if role ~= 'robber' or status.phase ~= 'active' then return end

    NickHUD.shard('THAT IS A HELICOPTER', 'They can see you. All of them. Get under something.')
end)

RegisterNetEvent('nick:end', function()
    clearBlips()

    if memo.hidden then
        memo.hidden = false
        TriggerServerEvent('nick:vanish', false)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearBlips()
end)
