-- The campaign. System tunables up top, then one entry per mission under
-- Config.missions - a mission is pure data: stages, spawns, set dressing.
-- Coords are hand-placed and safe to nudge in-game.
--
-- Stage types:
--   goto    - drive/walk to target
--   gather  - carry `require` jerry cans to deliverAt (cans come from the
--             mission's jerryCans list - and yes, they also pour into cars)
--   regroup - every connected player inside radius of target at once
--   holdout - survive `duration` seconds at target
Config = {
    -- ===== system =====

    -- Sidearm era: pistols only, and ammo is precious. Headshots or leg it.
    player = {
        weapon     = 'WEAPON_PISTOL',
        ammoStart  = 24,
        ammoReward = 30,
    },

    -- The crew look: same gang, different blokes. Models are dealt round-robin
    -- by join order and each gets randomised outfit components on top, so two
    -- players on the same base model still don't match.
    gang = {
        models = { 'g_m_y_lost_01', 'g_m_y_lost_02', 'g_m_y_lost_03', 'g_m_m_lost_01' },
    },

    -- Scripted vignettes: fired at one random player every minute or two.
    moments = {
        list  = { 'planecrash', 'crashcar', 'runner', 'helicopter', 'turning',
                  'ambulance', 'faller', 'stampede', 'tanker' },
        gapMs = { min = 40000, max = 85000 },
    },

    -- Ordinary bangers: fine for one or two, not the crew wagon.
    beaterModels  = { 'emperor2', 'tornado3', 'youga', 'moonbeam', 'regina', 'premier' },

    -- One motor each, dealt by join order, parked in a fan at the start line.
    -- Quick enough to race between objectives, scruffy enough to still be the
    -- apocalypse. Nobody waits for the van and nobody gets left behind.
    crewCars    = { 'futo', 'sultan', 'penumbra', 'blista', 'sentinel', 'buffalo' },
    -- How far out the fan of motors is parked. 8m put them close enough to
    -- land on whoever had just respawned at the same spot - a car dropping on
    -- somebody and flattening them was, in fairness, very funny, but it also
    -- cost them the round.
    crewCarRadius = 16.0,
    crewCarFuel = 60.0,
    wreckModels   = { 'emperor2', 'tornado3', 'regina', 'burrito3' },
    claimDistance = 150.0,

    jerryCanRefuel  = 40.0,
    jerryCanTrigger = 120.0,

    fuel = {
        drainIdlePerMin  = 1.5,
        drainDrivePerMin = 13.0,
        sputterBelow     = 15.0,
        sputterChance    = 0.35,
        sputterEveryMs   = 9000,
        refuelPerSec     = 4.0,
        stationRadius    = 15.0,
        ambientFuel      = { 10, 40 },
    },

    stations = {
        vector3(1039.9, 2671.3, 39.5),
        vector3(263.9, 2606.5, 45.0),
        vector3(49.4, 2778.8, 58.0),
        vector3(180.6, -1562.0, 29.3),
        vector3(-319.3, -1471.7, 30.5),
        vector3(1207.3, 2660.2, 37.9),
        vector3(2539.7, 2594.2, 37.9),
        vector3(1784.3, 3330.6, 41.3),
        vector3(-94.5, 6419.6, 31.5),   -- Paleto
        vector3(1687.0, 4929.0, 42.1),  -- Grapeseed
    },

    beaterFuelDefault  = { 15, 45 },
    beaterEngineHealth = { 350, 750 },

    -- Flash each new objective across the middle of the screen, not just into
    -- the corner. The corner line is easy to miss while something is chewing
    -- your leg, which is exactly when a new objective tends to arrive.
    stageShard = true,

    hud = {
        objX  = 0.015, objY  = 0.885,
        fuelX = 0.845, fuelY = 0.885,
        scale = 0.5,
    },

    -- Bleeding out. Die and you are DOWN, not gone: a mate who reaches the
    -- spot inside the window drags you back up, right where you fell.
    -- Every objective is defended: reach it and CLEAR THE WAVES to take it.
    -- secureWaveClears is how many full waves must go down before a secure
    -- stage completes (per-stage override: waveClears - the big beats take 2).
    -- Standing about for secureSeconds was too rushed a bar; now the horde
    -- decides when you're done, and the seconds survive only as a minimum
    -- floor. The floor still only ticks while somebody is holding the circle
    -- - on foot unless the stage says holdInVehicle - so shredding the wave
    -- from three streets away still means coming back to stand on the spot.
    -- A stage with secureSeconds = 0 stays instant: no floor, no waves.
    secureSeconds    = 30,
    secureWaveClears = 1,
    secureAmmo       = 18,

    reviveSeconds     = 20,  -- how long you bleed out for
    reviveRadius      = 5.0, -- how big the circle is
    reviveHoldSeconds = 5,   -- how long a mate must stand in it

    defaultMission = 'lastorders',

    -- ===== missions =====
    missions = {

        -- ============================================================
        -- EPISODE 2 - the A-to-B travel mission. Sticks into the city,
        -- waves swelling the closer you get to downtown.
        -- ============================================================
        lastorders = {
            label = 'Last Orders - the drive to the boat',
            shard = { title = 'LAST ORDERS', sub = 'Boat leaves Del Perro Pier at dawn. Don\'t be late.' },

            intro = {
                'The pub ran dry two days ago. Gaz drank the mixers.',
                'Radio says there\'s a boat at Del Perro Pier at dawn. Last one out.',
                'That\'s twenty miles of infected between here and there. Downhill, mind.',
            },

            start = { pos = vector3(1981.0, 3047.0, 47.1), heading = 300.0 },

            hordeFromStage   = 2,
            momentsFromStage = 2,
            cityIntensity    = {
                centre = vector3(215.0, -900.0, 30.0),
                base = 1.7, per = 3600.0, min = 0.5, max = 1.7,
            },

            stages = {
                { id = 'van', type = 'goto', target = vector3(1975.5, 3043.5, 46.8), radius = 60.0,
                  title = 'GET IN YOUR MOTOR', flavour = 'One each. First to Harmony picks the music.',
                  done = 'Engines running. Try to arrive in the same decade.',
                  -- Completes when someone is actually behind a wheel, then
                  -- fight the opening ambush off before you drive away from
                  -- it, done as a HOLD rather than a clear-the-area check.
                  --
                  -- requireClear cannot work here: the objective is to sit in
                  -- a car, and the horde comes to you, so there are always
                  -- infected within any radius you pick and the stage never
                  -- completes. Holding from the driver's seat gives the same
                  -- "earn it" beat and can actually be finished.
                  requireVehicle = true,
                  holdInVehicle = true, secureSeconds = 15,
                  -- Company from the off. Without this the first infected you
                  -- meet are the ones waiting at Harmony, so the opening leg
                  -- is a quiet drive through an empty map - the apocalypse
                  -- should be there before you have found a car.
                  ambush = true },
                { id = 'petrol', type = 'goto', target = vector3(1039.9, 2671.3, 39.5), radius = 28.0,
                  title = 'FILL UP AT HARMONY', flavour = 'Park at the pumps and wait for the tank. It takes a while.',
                  done = 'That glow over the city used to be streetlights. It\'s fires now.',
                  ambush = true,
                  -- Completes on a full tank, and the hold may be done from the
                  -- driver's seat: you cannot refuel a car you're stood next to.
                  requireFuel = 92, holdInVehicle = true, secureSeconds = 20 },
                { id = 'observatory', type = 'goto', target = vector3(-436.0, 1059.4, 327.7), radius = 35.0,
                  title = 'CHECK THE OBSERVATORY', flavour = 'Baz swears the army set up at the observatory.',
                  done = 'The army was NOT at the observatory. Baz owes everyone a pint.',
                  ambush = true, reward = 'ammo' },
                { id = 'hospital', type = 'goto', target = vector3(341.3, -1395.4, 32.5), radius = 30.0,
                  title = 'MEDS FOR GAZ', flavour = 'Gaz got scratched. He says it\'s fine. Get antibiotics anyway.',
                  done = 'Antibiotics acquired. Gaz says he feels "brilliant", which is worrying.',
                  -- The deep-city beat: heaviest garrisons, closest to
                  -- downtown, so the pharmacy costs two full waves.
                  waveClears = 2,
                  ambush = true, reward = 'armour' },
                { id = 'pier', type = 'goto', target = vector3(-1850.1, -1231.8, 13.0), radius = 35.0,
                  title = 'GET TO THE END OF THE PIER', flavour = 'Down the boardwalk. Don\'t stop to win a goldfish.',
                  done = 'Everyone on the pier. Nobody look at the sea.' },
                { id = 'boat', type = 'holdout', target = vector3(-1850.1, -1231.8, 13.0), radius = 60.0,
                  title = 'HOLD THE PIER', flavour = 'The boat\'s coming. Probably.',
                  duration = 240, waveEveryMs = 35000 },
            },

            win   = { title = 'LAST ORDERS', subtitle = 'The boat\'s here. Gaz brought the pint glasses.' },
            -- The boat that actually turns up, and where it takes you.
            winBoat = { model = 'dinghy', pos = vector4(-1855.0, -1250.0, 0.0, 120.0) },
            nextMission = 'departures',
            outro = {
                'The boat pulls away. Then the radio: "...anyone else out there... LSIA cargo terminal... Thursday..."',
                'Same time next week, then. Bring a jumper.',
            },

            garrisons = {
                { at = vector3(-425.0, 1071.0, 327.7),  count = 8,  trigger = 130.0 },
                { at = vector3(340.0, -1387.0, 32.5),   count = 10, trigger = 130.0 },
                { at = vector3(371.0, -1417.0, 32.3),   count = 6,  trigger = 110.0 },
                { at = vector3(-1660.0, -1125.0, 13.0), count = 8,  trigger = 140.0 },
                { at = vector3(-1770.0, -1195.0, 13.0), count = 8,  trigger = 110.0 },
            },

            beaterSpots = {
                -- Gaz's van lives on as a spare for whoever writes their car off.
                { pos = vector4(1975.5, 3043.5, 46.8, 240.0), model = 'youga', fuel = { 30, 36 }, plate = 'GAZ VAN' },
                { pos = vector4(1945.0, 3052.0, 46.9, 60.0), fuel = { 8, 16 } },
                { pos = vector4(1690.0, 3245.0, 41.2, 190.0) },
                { pos = vector4(1032.0, 2664.0, 39.5, 90.0), fuel = { 4, 10 } },
                { pos = vector4(380.0, 2620.0, 44.6, 95.0) },
                { pos = vector4(-415.0, 1080.0, 327.6, 200.0), fuel = { 20, 35 } },
                { pos = vector4(757.0, -740.0, 26.6, 90.0) },
                { pos = vector4(315.0, -1375.0, 32.6, 230.0), fuel = { 10, 25 } },
                { pos = vector4(-539.0, -1043.0, 23.2, 180.0) },
                { pos = vector4(-1655.0, -1090.0, 13.1, 300.0), fuel = { 5, 12 } },
            },

            wreckSpots = {
                { pos = vector4(1996.0, 3049.0, 47.0, 100.0), style = 'dead' },
                { pos = vector4(1045.0, 2662.0, 39.5, 95.0),  style = 'burning' },
                { pos = vector4(1370.0, 2680.0, 38.2, 180.0), style = 'dead' },
                { pos = vector4(-420.0, 1030.0, 323.0, 160.0), style = 'dead' },
                { pos = vector4(-432.0, 1046.0, 325.0, 340.0), style = 'scorched' },
                { pos = vector4(250.0, -1160.0, 29.2, 0.0),   style = 'dead' },
                { pos = vector4(190.0, -970.0, 30.2, 340.0),  style = 'burning' },
                { pos = vector4(330.0, -1380.0, 32.5, 320.0), style = 'scorched', model = 'ambulance' },
                { pos = vector4(352.0, -1405.0, 32.3, 140.0), style = 'burning', model = 'police2' },
                { pos = vector4(315.0, -1392.0, 32.4, 50.0),  style = 'dead' },
                { pos = vector4(-1655.0, -1110.0, 13.2, 220.0), style = 'dead' },
                { pos = vector4(-1680.0, -1140.0, 11.5, 40.0),  style = 'scorched', model = 'surfer2' },
            },

            jerryCans = {
                { pos = vector3(1050.0, 2673.0, 39.5),   guards = 4 },
                { pos = vector3(380.0, 2624.0, 44.6),    guards = 4 },
                { pos = vector3(-430.0, 1066.0, 327.7),  guards = 5 },
                { pos = vector3(263.9, 2610.0, 45.0),    guards = 4 },
                { pos = vector3(180.6, -1558.0, 29.3),   guards = 6 },
                { pos = vector3(-322.0, -1468.0, 30.5),  guards = 6 },
                { pos = vector3(-1652.0, -1095.0, 13.1), guards = 5 },
            },

            -- Ammo out in the world, all of it guarded. This is the answer
            -- to "where do I get more bullets" now that waves no longer run
            -- during the drive.
            ammoStashes = {
                { pos = vector3(1968.0, 3037.0, 46.9),  guards = 0, rounds = 18 }, -- behind the pub
                { pos = vector3(1044.0, 2665.0, 39.5),  guards = 4, rounds = 24 }, -- Harmony
                { pos = vector3(-433.0, 1072.0, 327.7), guards = 5, rounds = 30 }, -- observatory
                { pos = vector3(345.0, -1390.0, 32.5),  guards = 6, rounds = 30 }, -- hospital
                { pos = vector3(-1666.0, -1120.0, 13.1), guards = 5, rounds = 24 }, -- pier
                { pos = vector3(-1845.0, -1228.0, 13.0), guards = 0, rounds = 36 }, -- pier end, for the holdout
            },

            setPieces = {},
        },

        -- ============================================================
        -- EPISODE 3 - the gather mission. Hub-and-spoke sorties from
        -- the plane: five cans in, everything at the airport disagrees.
        -- ============================================================
        departures = {
            label = 'Departures - fuel the plane at LSIA',
            shard = { title = 'DEPARTURES', sub = 'There is a plane. There is no fuel in it.' },

            intro = {
                'Thursday. LSIA cargo terminal, like the radio said.',
                'There is a plane. There is no fuel in it. There is a theme developing.',
                'Five cans minimum, Gaz reckons. Gaz failed GCSE maths.',
            },

            start = { pos = vector3(-1336.0, -3044.0, 13.9), heading = 330.0 },

            hordeFromStage   = 2,
            momentsFromStage = 2,
            intensityFlat    = 1.15,

            stages = {
                { id = 'plane', type = 'goto', target = vector3(-1360.0, -3060.0, 13.9), radius = 25.0,
                  title = 'FIND THE PLANE', flavour = 'It\'s the big one. Allegedly it flies.',
                  done = 'It has wings. Most of them.' },
                { id = 'fuel', type = 'gather', target = vector3(-1360.0, -3060.0, 13.9),
                  deliverAt = vector3(-1360.0, -3060.0, 13.9), radius = 16.0, require = 5,
                  title = 'FUEL THE PLANE',
                  flavour = 'Cans are scattered round the airport. Bring them back. Try not to drink any.',
                  done = 'She\'s fuelled. That noise is normal, probably.', ambush = true },
                { id = 'apron', type = 'holdout', target = vector3(-1360.0, -3060.0, 13.9), radius = 60.0,
                  title = 'HOLD THE APRON', flavour = 'Engines spooling. Everything in Los Santos heard them.',
                  duration = 180, waveEveryMs = 30000 },
            },

            win   = { title = 'WHEELS UP', subtitle = 'Nobody look at the fuel gauge. NOBODY look at the fuel gauge.' },
            nextMission = 'waterlanding',
            outro = {
                '"...next stop Paleto, quick hop up the coast, trust me..."',
                'The starboard engine makes a new sound. Same time next week.',
            },

            garrisons = {
                { at = vector3(-1037.0, -2736.0, 13.9), count = 8,  trigger = 130.0 }, -- terminal front
                { at = vector3(-1267.0, -3141.0, 13.9), count = 8,  trigger = 120.0 }, -- apron
                { at = vector3(-1520.0, -3205.0, 13.9), count = 8,  trigger = 120.0 }, -- west hangars
                { at = vector3(-980.0, -2995.0, 13.9),  count = 6,  trigger = 110.0 },
            },

            beaterSpots = {
                { pos = vector4(-1330.0, -3050.0, 13.9, 330.0), fuel = { 20, 35 } },
                { pos = vector4(-1082.0, -2894.0, 13.9, 150.0), fuel = { 10, 25 } },
                { pos = vector4(-1420.0, -3175.0, 13.9, 60.0),  fuel = { 8, 20 } },
                { pos = vector4(-1030.0, -2725.0, 13.9, 240.0), fuel = { 15, 30 } },
            },

            wreckSpots = {
                { pos = vector4(-1050.0, -2750.0, 13.9, 200.0), style = 'burning' },
                { pos = vector4(-1230.0, -3060.0, 13.9, 90.0),  style = 'scorched' },
                { pos = vector4(-1390.0, -3110.0, 13.9, 10.0),  style = 'dead' },
                { pos = vector4(-1140.0, -2860.0, 13.9, 300.0), style = 'dead', model = 'ambulance' },
                { pos = vector4(-1005.0, -2905.0, 13.9, 45.0),  style = 'burning', model = 'police2' },
            },

            -- The mission items. Seven cans, five needed - the spare two are
            -- for whoever "tests" one in a car.
            jerryCans = {
                { pos = vector3(-1037.0, -2730.0, 13.9),  guards = 5 },
                { pos = vector3(-1267.0, -3148.0, 13.9),  guards = 4 },
                { pos = vector3(-1145.0, -2864.0, 13.9),  guards = 4 },
                { pos = vector3(-1520.0, -3212.0, 13.9),  guards = 5 },
                { pos = vector3(-980.0, -3002.0, 13.9),   guards = 5 },
                { pos = vector3(-1620.0, -2900.0, 13.9),  guards = 4 },
                { pos = vector3(-871.0, -2915.0, 16.0),   guards = 4 },
            },

            ammoStashes = {
                { pos = vector3(-1350.0, -3055.0, 13.9), guards = 0, rounds = 24 },
                { pos = vector3(-1040.0, -2735.0, 13.9), guards = 5, rounds = 30 },
                { pos = vector3(-1515.0, -3208.0, 13.9), guards = 5, rounds = 30 },
                { pos = vector3(-985.0, -2998.0, 13.9),  guards = 4, rounds = 24 },
            },

            setPieces = {
                { model = 'titan', pos = vector4(-1360.0, -3060.0, 13.9, 60.0) },
            },
        },

        -- ============================================================
        -- EPISODE 4 - the split-up mission. Everyone washes ashore
        -- alone along Paleto Bay, at night, and walks to the pub.
        -- ============================================================
        waterlanding = {
            label = 'Water Landing - washed up, find each other',
            shard = { title = 'WATER LANDING', sub = 'The plane made it seventy miles. Find the others.' },

            intro = {
                'The plane made it seventy miles.',
                'Bits of it are all along Paleto Bay. So are you.',
                'There\'s a pub in Paleto. Obviously that\'s the meeting point.',
            },

            start = { pos = vector3(-292.0, 6256.0, 31.4), heading = 0.0 },
            -- One per player, round-robin. Alone, wet, one pistol.
            scatterSpawns = {
                vector3(-140.0, 6870.0, 4.0),
                vector3(-330.0, 6780.0, 3.0),
                vector3(-560.0, 6690.0, 4.5),
                vector3(-790.0, 6590.0, 6.0),
                vector3(-1030.0, 6480.0, 5.0),
                vector3(-1350.0, 6370.0, 8.0),
            },

            hordeFromStage   = 1, -- the walk is NOT safe
            momentsFromStage = 1, -- a burning plane overhead while you're alone? yes.
            intensityFlat    = 0.75,

            stages = {
                { id = 'meet', type = 'regroup', target = vector3(-292.0, 6256.0, 31.4), radius = 25.0,
                  title = 'GET TO THE PUB IN PALETO',
                  flavour = 'Alone is bad. Pub is good. Walk.',
                  done = 'Reunion. Gaz hugged everyone. Gaz smells of kelp.' },
                { id = 'lockin', type = 'holdout', target = vector3(-292.0, 6256.0, 31.4), radius = 60.0,
                  title = 'LOCK-IN', flavour = 'The whole bay heard the crash.',
                  duration = 150, waveEveryMs = 35000 },
            },

            win   = { title = 'STAY FOR ONE MORE', subtitle = 'Alive, together, and the taps still work.' },
            outro = {
                'The radio, through static: "...the army is at Zancudo... repeat, the army IS at Zancudo..."',
                'Baz, vindicated at last. Same time next week.',
            },

            garrisons = {
                { at = vector3(-292.0, 6248.0, 31.4),  count = 8, trigger = 120.0 }, -- pub approach
                { at = vector3(-160.0, 6560.0, 31.0),  count = 5, trigger = 110.0 }, -- beach road east
                { at = vector3(-560.0, 6520.0, 20.0),  count = 5, trigger = 110.0 }, -- beach road west
                { at = vector3(-680.0, 5990.0, 17.0),  count = 5, trigger = 110.0 }, -- coast highway
            },

            beaterSpots = {
                { pos = vector4(-275.0, 6330.0, 32.0, 45.0),  fuel = { 10, 25 } },
                { pos = vector4(-378.0, 6220.0, 31.8, 135.0), fuel = { 8, 20 } },
                { pos = vector4(-90.0, 6420.0, 31.5, 220.0),  fuel = { 5, 12 } },
                { pos = vector4(-450.0, 6560.0, 15.0, 300.0), fuel = { 10, 20 } },
                { pos = vector4(-800.0, 6420.0, 15.0, 60.0),  fuel = { 10, 22 } },
                { pos = vector4(-1150.0, 6300.0, 20.0, 120.0), fuel = { 8, 18 } },
            },

            -- "Plane debris": burning and scorched wrecks along the shoreline.
            wreckSpots = {
                { pos = vector4(-260.0, 6720.0, 6.0, 20.0),  style = 'burning' },
                { pos = vector4(-520.0, 6650.0, 8.0, 200.0), style = 'scorched' },
                { pos = vector4(-880.0, 6540.0, 10.0, 90.0), style = 'burning' },
                { pos = vector4(-240.0, 6300.0, 31.5, 310.0), style = 'dead' },
                { pos = vector4(-330.0, 6260.0, 31.4, 50.0),  style = 'scorched' },
            },

            jerryCans = {
                { pos = vector3(-94.5, 6415.0, 31.5),  guards = 4 },
                { pos = vector3(1687.0, 4929.0, 42.1), guards = 4 },
            },

            ammoStashes = {
                { pos = vector3(-286.0, 6262.0, 31.5), guards = 0, rounds = 24 }, -- the pub
                { pos = vector3(-160.0, 6555.0, 31.0), guards = 4, rounds = 24 },
                { pos = vector3(-565.0, 6516.0, 20.0), guards = 4, rounds = 24 },
            },

            setPieces = {},
        },
    },
}
