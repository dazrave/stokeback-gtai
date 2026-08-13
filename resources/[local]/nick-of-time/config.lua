-- Nick of Time. One robber, everyone else is the law, ten minutes on the clock.
-- Loot the shops, stash it at a safehouse, and only what you physically got
-- through a safehouse door counts. Every tunable lives here.
--
-- The KEY NAMES in the blocks below are Darren's own, copied verbatim out of
-- the scope doc (docs/modes/nick-of-time.md) so a knob he wrote down is a knob
-- he can find with ctrl-F. Anything this file adds on top of that draft is
-- marked (+); anything the draft has that night one does not read yet is
-- marked (wishlist) so nobody wastes an evening tuning a number nothing uses.
Config = {

    -- ===== the round =====
    round = {
        ROUND_LENGTH_S     = 600,  -- 10:00 hard cap, the whole pitch
        SHOW_DELTA_TO_COPS = true, -- the spectators knowing before the driver does

        -- (+) Grace before the clock starts. Roles go out 1.5s after the round
        -- is set up and a client can spend another 2.5s waiting for collision
        -- to stream, so a countdown started at setup was most of the way
        -- through before anyone could see it. Chase learned this the hard way.
        READY_S = 4,

        -- (+) No head start, deliberately. The police start at their own
        -- muster point with NO CONTACT - they genuinely do not know where he
        -- is - so freezing everyone for three seconds would only be theatre.
        -- Dusk and clear, locked, identical for every round of the match: the
        -- scope's fairness requirement is that nobody gets an easier city.
        CLOCK       = { hour = 19, minute = 40, weather = 'CLEAR', freeze = true },
        MIN_PLAYERS = 2, -- one robber, one copper. Anything less is a walk.

        -- (+) How long a session (seed, scoreboard, rota) survives on disk.
        -- Long enough that PUSH LIVE mid-evening never wipes a match; short
        -- enough that next Thursday starts fresh instead of replaying last
        -- week's seed against last week's scoreboard.
        SESSION_MAX_AGE_H = 18,
    },

    -- ===== detection: hard lock / drifting soft track / cold =====
    -- The heart of the mode. A copper only ever gets the truth by LOOKING at
    -- him. Lose him and the map keeps showing where he WOULD be if he carried
    -- straight on - which is wrong the moment he doubles back, and being wrong
    -- is the entire point.
    detection = {
        LOS_TICK_HZ            = 5,
        LOS_GRACE_MS           = 1500, -- unbroken loss before dropping to soft track
        LOS_FLAGS              = 23,   -- world + vehicles + objects
        SOFT_TRACK_DRIFT_DECAY = 0.85, -- how fast heading confidence dies (per second)

        -- Slower swell and a later cold call than the draft (12/400): night
        -- one's verdict was "well too hard to find the robber", and the
        -- cheapest honest help is a search circle that stays information for
        -- longer instead of giving up on itself.
        SOFT_TRACK_GROWTH_MPS  = 10,   -- the search circle swells this fast
        SOFT_TRACK_COLD_RADIUS = 500,  -- past this the circle is useless: go cold

        HELI_PROXIMITY_ICON_RADIUS = 250, -- the piloted heli's icon on the ROBBER'S map

        -- (+) How far a copper can see, borrowed from chase where these
        -- numbers have survived a season of Thursdays. Air range is double
        -- because that is the only reason to take a helicopter.
        SIGHT_GROUND_RANGE = 120.0,
        SIGHT_AIR_RANGE    = 250.0,

        -- (+) The circle a fresh sighting collapses back to. Without a floor
        -- the "search area" starts as a dot on top of him, which reads as a
        -- live lock rather than a last-known.
        SOFT_TRACK_BASE_RADIUS = 40.0,

        -- (+) The guess drifts at the speed he was doing between the last two
        -- sightings. Capped so one dodgy pair of pings can't fling the circle
        -- across the map at 300mph.
        SOFT_TRACK_MAX_DRIFT_MPS = 30.0,
    },

    -- ===== rubber banding =====
    -- "No cop car catches the robber on straights alone." Every catch should
    -- trace back to a corner, a cutoff or a burst tyre - so the law gets help
    -- closing a GAP, never help winning a drag race.
    banding = {
        BAND_START_DISTANCE      = 250,   -- boost begins beyond this

        -- 1.25 -> 1.35 once the band actually applied (it had never worked -
        -- see police.lua's per-frame note): a cruiser at full stretch should
        -- roughly HOLD a straight against the robber pool, uphill included,
        -- and still only ever CLOSE through a corner or a cutoff - the
        -- close-range cap below BAND_START_DISTANCE is what keeps that true.
        BAND_MAX_MULTIPLIER      = 1.35,
        BAND_POWER_WEIGHT        = 0.7,   -- bias toward acceleration over top speed
        POLICE_SPEED_FLOOR_PCT   = 0.80,  -- stops a robber griefing in a slow vehicle
        AI_PATROLS_RUBBER_BANDED = false, -- (wishlist) night one has no AI patrols

        -- (+) Distance is measured to what DISPATCH says, not to the truth -
        -- the boost must never become a radar the police can feel their way
        -- along. While the trail is cold there is no boost at all.
        BAND_FULL_DISTANCE = 600, -- band reaches BAND_MAX_MULTIPLIER out here
    },

    -- ===== vehicle damage =====
    -- The getaway car dying is the best joke in the mode: it stutters, it
    -- catches, and then it puts you across a pavement in front of three squad
    -- cars. Non-negotiable that it never actually kills him (see nonLethal).
    damage = {
        DAMAGE_STUTTER_THRESHOLD = 0.10,        -- engine health fraction the cough starts at
        DAMAGE_STUTTER_MS        = { 200, 400 }, -- how long each cut-out lasts
        DAMAGE_HITS_TO_FIRE      = 2,            -- more punishment while critical and she goes up
        FIRE_TO_EXPLOSION_MS     = 6000,         -- from flames to the fireball: time to bail
        RAM_DAMAGE_SPEED_SCALING = true,         -- (wishlist) GTA already scales ram damage
        COP_VEHICLES_TAKE_DAMAGE = true,

        -- (+) A shunt, not a scrape. Body health runs to 1000, so brushing a
        -- bollard costs a couple of points while a proper ram costs tens -
        -- without this the allowance evaporates at the first busy junction.
        MIN_RAM_DAMAGE   = 15.0,
        STUTTER_EVERY_MS = 1800, -- gap between coughs, or it is simply undriveable

        -- (+) What a counted ram costs the ENGINE, out of 1000. GTA puts
        -- collision damage almost entirely into panels, so a car rammed all
        -- round the block still had a healthy engine and the ladder's stutter
        -- and stop never fired - night one's "there's no car health?". This
        -- is the coupling that makes ramming the strategy the plan says it
        -- is: seven or so proper shunts and she is done.
        RAM_ENGINE_COST = 130.0,

        -- (+) The plan's ladder, in full: burst/ram -> degrade -> STOP -> pull
        -- out -> foot chase -> tase -> arrest. The "stop" rung was missing;
        -- she used to cough all the way to the fireball. Now the engine
        -- actually gives up at the bottom, and the fire is what happens to a
        -- car that is already dead and still being rammed.
        DEAD_ENGINE_THRESHOLD = 0.02, -- engine fraction at or below: cuts out for good

        -- (+) GTA lights a badly damaged petrol tank on its own schedule,
        -- which would end rounds with a random fireball nobody caused. The
        -- tank is clamped so the ONLY thing that ever sets her alight is the
        -- ladder above (plan §11, "GTA self-igniting damaged vehicles").
        PETROL_TANK_CLAMP = 1000.0,

        -- (+) Plan §5.2: the blast throws him clear. It is the safety
        -- requirement AND the joke, so it is not optional - a fireball that
        -- killed him would end the round in a way the scope never lists.
        ROBBER_EXPLOSION_PROOF = true,

        -- (+) Plan §5.2 again: guns become tyre tools by construction. He
        -- cannot be shot out of the driver's seat, so a pursuit ends by
        -- stopping the car, not by emptying a magazine through the rear
        -- windscreen. On foot he is still shootable (the floor keeps him
        -- alive) - full bulletproofing is one knob away once the taser has
        -- had a night out.
        ROBBER_SHOT_IN_VEHICLE = false,
    },

    -- ===== the pull-out =====
    -- (+) Plan §5.2, "jack, never enter": the cop is NEVER given an enter task,
    -- so he can never end up sat in the robber's seat wearing his getaway car.
    -- The whole interaction is a task on the ROBBER'S ped (his own machine owns
    -- it) plus a paired animation, and the cop is left stood in the road
    -- looking pleased with himself.
    jack = {
        RADIUS      = 4.5,  -- cop on foot this close to the car...
        MAX_SPEED   = 8.0,  -- ...doing under about 18mph
        HOLD_MS     = 600,  -- at the window this long before the door opens
        LEAVE_FLAGS = 4160, -- TaskLeaveVehicle: jacked out, door left swinging
        RAGDOLL_MS  = 1500, -- and onto the tarmac

        -- Paired animation, guarded: if the dictionary will not stream the
        -- ragdoll still sells it, so a missing anim can never eat the arrest.
        ANIM_DICT   = 'random@mugging3',
        ANIM_COP    = 'struggle_loop_a_thief',
        ANIM_ROBBER = 'struggle_loop_a_victim',
        ANIM_MS     = 1200,

        -- (+) What she says while she dies, in order, looping. The car's
        -- decline getting its own commentary is half the reason anyone tells
        -- the story afterwards.
        COUGH_LINES = {
            'She is coughing.',
            'That is not a good noise.',
            'Talk to her. Encourage her.',
            'She is doing her best.',
            'Third gear is a memory now.',
        },
    },

    -- ===== looting =====
    looting = {
        FILL_RATE_BASE         = 1200,           -- value per second at full stock
        FILL_RATE_DECAY        = 0.6,            -- slows as location depletes
        ALARM_QUIET_BAND_S     = { 15, 40 },     -- hidden timer, never shown to him
        ALARM_SMASH_DELAY_S    = 0,              -- smash-and-grab: it goes off as the glass lands
        PUBLIC_VALUE_UPDATE_ON = 'alarm_or_exit', -- never live, or the map tracks him

        -- (+) Stand-in-the-zone radius. Small on purpose: he is behind the
        -- counter, not loitering on the forecourt.
        ZONE_RADIUS = 4.0,

        -- (+) The SERVER'S slack on that zone, as a multiplier. The server
        -- reads his position off its own copy of the ped, and OneSync lags
        -- that copy metres behind a SPRINTING man - which is why night one
        -- read as "once you've been spotted, no more stealing": chased in at
        -- a run, the prompt shows (client-true) but the till refuses
        -- (server-stale). Wide enough to forgive the sprint, still tight
        -- enough to stop the impossible.
        START_SLACK = 3.0,

        -- (+) The smash-and-grab trade, spelled out. You are through the glass
        -- and filling the bag faster, but half the till is in a drawer you are
        -- never getting into and the bell is already ringing.
        SMASH_TAKE_PCT   = 0.6,
        SMASH_FILL_MULT  = 1.5,

        -- (+) What a tier 1 site holds. The scope's tier 2 (Fleeca) and tier 3
        -- (jeweller, the big bank) are wishlist and need IPL names alongside
        -- the coordinate, so they are not here yet.
        tiers = {
            cornerShop = { label = 'Convenience store', stock = 9000 },
        },
        DEFAULT_TIER = 'cornerShop',

        -- (+) Plan §4.3, cars as loot. Nick something exotic and it rides on
        -- your ON YOU total at value x health%, so being rammed bleeds the
        -- payout in real time and a wreck is worth nothing. Model names, not
        -- coordinates - nothing here needs the tag board.
        --
        -- Cashing one in is a safehouse job like any other bag: it is the
        -- getting there that costs you, because you are driving the most
        -- conspicuous car in Los Santos with the entire force looking for you.
        CARS = {
            ENABLED = true,
            VALUES  = {
                adder      = 45000, zentorno   = 40000, t20      = 42000,
                osiris     = 38000, italigtb   = 36000, entityxf = 35000,
                nero       = 34000, pfister811 = 33000, tempesta = 32000,
                reaper     = 30000, comet2     = 18000, banshee  = 16000,
            },
        },
    },

    -- ===== safehouses =====
    safehouses = {
        SAFEHOUSE_POOL           = 10,
        SAFEHOUSE_PER_ROUND      = 5,
        SAFEHOUSE_ENTRY_CLEAR_MS = 1000, -- unseen for this long inside and you vanish
        SAFEHOUSE_REVEAL_ON_USE  = true, -- banking is loud: the door gets pinged

        -- (+) The dive zone, and the bucket he vanishes into. Routing buckets
        -- are how a player genuinely disappears rather than merely being hard
        -- to see - the whole force can drive through him and never know.
        ZONE_RADIUS    = 6.0,
        HIDDEN_BUCKET  = 71, -- arbitrary, just not 0 (the world everyone else is in)

        -- (+) Ending the round is a held G, not a tapped one. G is also the
        -- smash-and-grab key, and one loose tap at a door cost Rory a £6,428
        -- bag on the default map's first night. Long enough to be deliberate,
        -- short enough that a man who means it is not stood there feeling silly.
        CALLIT_HOLD_MS = 1500,

        -- (+) Server slack on the stash zone, same disease as the tills
        -- (looting.START_SLACK): he DIVES into safehouses at a dead run with
        -- the force behind him, and the server's copy of him is still on the
        -- pavement. A refused bank at the door is a lost round, not a fair cop.
        STASH_SLACK = 2.5,
    },

    -- ===== escalation =====
    -- Greed is the game (pillar 4): every star he earns is a star he chose to
    -- earn by banking instead of running. And pillar 3 is absolute - none of
    -- the machinery below can arrest, shoot, or end a round. It exists to
    -- generate INFORMATION and PRESSURE for the humans, nothing else.
    escalation = {
        VALUE_PER_STAR   = 10000,
        AI_CARS_PER_STAR = 1,
        AI_CARS_MAX      = 6,
        AI_RELAY_RADIUS  = 120, -- while a patrol is this close he is on the humans' maps

        BONUS_HELI_CONTACT_THRESH = 0.15, -- team contact score below this unlocks it
        BONUS_HELI_PING_S         = 20,
        BONUS_HELI_USES_PER_ROUND = 1,

        ROADBLOCK_START_S          = 420,  -- (blocked on tagging: chokepoints)
        ROADBLOCK_REQUIRES_PURSUIT = true, -- (blocked on tagging)
        ROADBLOCK_MAP_WARNING_S    = 5,    -- (blocked on tagging)

        -- (+) How long an alarm, a witness call or a stash ping sits on the
        -- map before the trail it represents is stale enough to be a lie.
        PING_LIFE_MS = 45000,

        -- (+) The patrols themselves. Unarmed, neutral, follow-only, and
        -- capped hard: CPointRoute has FORTY route slots for the entire game
        -- and every vehicle on a navmesh task holds one, so six is a budget
        -- decision as much as a balance one (AGENTS.md, the gotcha that
        -- hard-crashes clients).
        AI_MODELS           = { 'police', 'police2', 'police3' },
        AI_DRIVER           = 's_m_y_cop_01',
        AI_SPAWN_DISTANCE   = { 130.0, 240.0 }, -- far enough not to appear in his mirror
        AI_DESPAWN_DISTANCE = 420.0,
        AI_SPAWN_EVERY_MS   = 12000, -- they arrive over time, never all at once
        AI_FOLLOW_OFFSET    = 25.0,  -- they hang back: a tail, not a ram
        AI_RETASK_MS        = 9000,  -- a vehicle task quietly expires; re-issue it

        -- (+) The bonus heli. Cosmetic AI, high, one pass, then it goes home.
        -- Its ping is UNCONDITIONAL (plan §5.3): it is a rare lifeline earned
        -- by a team that has genuinely lost him, and a lifeline that respects
        -- cover would be no lifeline at all.
        BONUS_HELI_MODEL  = 'polmav',
        BONUS_HELI_PILOT  = 's_m_y_cop_01',
        BONUS_HELI_HEIGHT = 65.0,
        BONUS_HELI_LIFE_S = 32, -- outlives the ping by a beat, then leaves

        -- (+) Contact score: the share of the round the force has actually
        -- had a hold of him, counting eyes-on AND merely being near him. Low
        -- score = they are chasing a rumour = the heli unlocks.
        CONTACT_NEAR_M   = 150.0,
        CONTACT_MIN_S    = 60, -- no unlock in the opening minute; it is not a start bonus

        -- (+) OneSync culls distant players out of existence client-side,
        -- which would make a helicopter's whole job impossible. Airborne
        -- police get a bigger bubble (plan §5.3).
        CULLING_RADIUS_AIR = 1200.0,
    },

    -- ===== the air unit =====
    -- (+) Darren, game night: "I thought we could spawn and pilot our own
    -- Heli?" - the scope always meant one (manually piloted helicopter, with
    -- the proximity icon), it just shipped wishlist. Now: any copper types
    -- /heli and a bird lands on the pad for whoever goes and gets it. No
    -- magic on board - the air gets SIGHT_AIR_RANGE eyes and nothing else,
    -- the same LOS rules as the ground, and the robber gets the proximity
    -- icon (detection.HELI_PROXIMITY_ICON_RADIUS) as his fair warning.
    airUnit = {
        ENABLED      = true,
        MODEL        = 'polmav',
        COMMAND      = 'heli',
        PER_ROUND    = 2,     -- ask again after you put the first one in the sea
        SPAWN_WITHIN = 200.0, -- materialises when its collector gets this close to the pad
    },

    -- ===== witness-modelled incident calls =====
    -- (+) Plan §3.4. A crash only gets phoned in if somebody was actually
    -- there to see it: empty docks at 3am, silence; Vespucci Beach, instant
    -- call. The call reports a POINT and never a direction - two of them let
    -- the police work out a bearing themselves, which is skill rather than a
    -- handout. This is the whole reason the city is left populated.
    witness = {
        ENABLED      = true,
        RADIUS       = 80.0, -- an NPC this close, with a clear look at him
        MAX_CHECKED  = 10,   -- peds tested per incident; keep it off the frame budget
        CRASH_DAMAGE = 40.0, -- body health lost in one go to count as a crash
        DELAY_S      = { 4, 10 }, -- a 999 call takes a moment to reach anyone
        GAP_S        = 18,   -- at most one call per this, or a bad driver is a tracker

        -- (+) Night one's finding-game retune: RADIUS 70->80, DELAY {5,15}->
        -- {4,10}, GAP 25->18. More of the city phones things in, faster - the
        -- calls were so rare and so late that "no 999 calls when crashing"
        -- was a fair review of a system that technically existed.

        -- (+) LOUD events are HEARD, not seen. A crash this big waives the
        -- line-of-sight check - a wall between the witness and a car folding
        -- itself round a lamppost does not stop the phone call. The NPC still
        -- has to exist and be in RADIUS: the empty docks stay silent.
        LOUD_CRASH_DAMAGE = 120.0,

        -- (+) Gunfire near him gets phoned in the same way (heard, no LOS).
        -- The ping still lands on the SERVER'S read of the robber - the
        -- caller reports "shots around there", not a bearing - and a copper
        -- must already be this close to him to set one off, so it cannot be
        -- fished from across the map. Firing a warning shot to make the
        -- neighbourhood do your job is legitimate policing on this server.
        GUNFIRE        = true,
        GUNFIRE_RADIUS = 60.0,
    },

    -- ===== auto-GPS =====
    -- (+) Plan §5.6. The police radio never says "he is at X" - the route line
    -- does, off the best thing currently known. The ladder is strict priority
    -- with hysteresis, so it cannot flap between two near-equal leads and turn
    -- the minimap into a strobe.
    gps = {
        ENABLED            = true,
        HOLD_MS            = 6000,  -- stay on a target at least this long
        WITNESS_FRESH_S    = 25,    -- a call older than this stops being a lead
        MANUAL_SUPPRESS_MS = 20000, -- a hand-placed waypoint wins, for a bit

        -- (+) The manual half (Darren, game night: "allow a person manual gps
        -- as well as the one when there's an alarm"). /gps asks dispatch for
        -- its best RIGHT NOW: drops your own waypoint, ends the suppression,
        -- rebuilds the route - and control tells you what kind of lead you
        -- are being routed at. Police only; the robber gets a brush-off.
        MANUAL_COMMAND = 'gps',
    },

    -- ===== robber awareness =====
    -- He never gets to see the police on his map - he gets a feeling. Three
    -- states, delayed, so he is always reacting to something that was true a
    -- moment ago.
    pressure = {
        PRESSURE_RADIUS          = 400,
        PRESSURE_STATES          = 3,
        PRESSURE_UPDATE_DELAY_MS = 1500,

        -- Density, not distance, and the AI half is capped: at five stars the
        -- bar must still have somewhere to go when a HUMAN turns the corner.
        -- A meter pegged by patrols would tell him nothing and cost him the
        -- one warning that matters.
        PRESSURE_AI_CONTRIBUTION = 0.33,

        ROBBER_INFINITE_STAMINA  = true, -- the foot chase should end in a taser, not a wheeze
    },

    -- ===== the arrest =====
    -- (+) Chase's numbers, unchanged: a copper on foot, this close, to someone
    -- moving slower than a jog.
    arrest = {
        RANGE     = 3.0,
        MAX_SPEED = 2.5,

        -- (+) Server-side slack on the same two numbers. The client shows
        -- the prompt; the server checks the cuffs actually reach - these are
        -- the latency allowance so an honest arrest never bounces, while an
        -- arrest pressed from the other side of the map still does.
        RANGE_SLACK = 3.0,
        SPEED_SLACK = 2.0,
    },

    -- ===== non-lethal by law =====
    -- (+) Straight out of chase. The scope lists exactly three endings -
    -- arrest, call it a day, the clock - and none of them is "shot dead in a
    -- car park", so gunfire has to be able to stop him without finishing him.
    -- Enforced on the ROBBER'S OWN CLIENT, which is the machine that owns his
    -- ped, so no shot from anywhere can ever put him under the floor.
    nonLethal = {
        enabled     = true,
        floorHealth = 110, -- 100 is death, so this leaves him on his last legs
        limpBelow   = 140,
        knockdown   = {
            enabled = true,
            everyMs = 6000, -- can't be chain-stunned into a permanent nap
            downMs  = 4500, -- the window to actually cuff him
        },

        -- (+) The floor above is enforced per frame, and a petrol tank going
        -- up or a long swim can take him from fine to dead inside one - and a
        -- dead robber with no respawn is ten minutes of everyone watching a
        -- corpse. So he gets up where he fell (the bag lives on the server,
        -- it survives with him), and the delay is the law's window to walk
        -- over and nick the body first.
        DIED_RESPAWN_S = 8,
    },

    -- ===== who spawns with what =====
    -- Models only for the cars: the fleet is laid out along the nearest ROAD
    -- at spawn time, because hand-typed coordinates park cars inside the
    -- building. Kits are core's (core/shared/loadouts.lua) - the mode only
    -- names one. 'taser' is the cop kit plus the stun gun, because the scope
    -- is explicit that the foot chase ends with a taser, not a shootout.
    kit = {
        POLICE_LOADOUT = 'taser',
        POLICE_AMMO    = 250,
        TASER_WEAPON   = 'WEAPON_STUNGUN', -- what the robber's knockdown listens for
    },

    models = {
        police = 's_m_y_cop_01',
        robber = 'a_m_y_downtown_01', -- looks like anyone else on the street, which is the point
    },

    vehicles = {
        POLICE       = { 'police', 'police2', 'police3', 'fbi2' },
        ROBBER       = { 'futo', 'blista', 'asterope', 'premier' }, -- ordinary cars keep everyone on the same roads
        FLEET_SPACING = 9.5, -- nose to tail down the kerb; under a car length and they shove each other
    },

    -- Cops are never out of the round: wrecking your car costs you the chase,
    -- not the evening. Plan §7 phase 3: back on the nearest road, with a
    -- fresh vehicle, ~15 seconds later.
    police = {
        RESPAWN_S        = 15,
        RESPAWN_TO_ROAD  = true, -- dying in a field must not end your evening
        RESPAWN_WITH_CAR = true,

        -- The other way to end up stranded: you survived, your cruiser did
        -- not. Nothing drivable within RELIEF_RADIUS for this long and one
        -- turns up on the nearest road.
        RELIEF_AFTER_S = 10,
        RELIEF_RADIUS  = 30.0,
    },

    -- E to work / stash / nick him, G for the loud option, for calling it a
    -- day, and for calling in the favour.
    controls = {
        PRIMARY   = 38, -- INPUT_PICKUP (E)
        SECONDARY = 47, -- INPUT_DETONATE (G)
        -- ~INPUT_*~ tokens only resolve in help text, not in the draw-text
        -- HUD - there they come out as raw glyph codes ("press b_6").
        -- The HUD prints this instead; change it if you rebind SECONDARY.
        SECONDARY_LABEL = 'G',
    },

    hud = { x = 0.5, y = 0.055, scale = 0.55 },

    -- ===== the retelling =====
    -- (+) None of this affects play. It is the material the room quotes back
    -- at each other at the bar afterwards, which for this crowd is the score
    -- that actually matters. Every line and list lives here.
    flavour = {
        -- What control calls the suspect over the radio, drawn once from the
        -- session seed and then used all evening. The consistency is the
        -- joke: by round three everyone is calling him it too.
        EPITHETS = {
            'the gentleman', 'our friend', 'chummy',
            'the entrepreneur', 'his nibs', 'matey boy',
        },

        -- Control's running commentary as the picture changes. %s is the
        -- epithet. Police ears only - the robber is never told the map has
        -- gone quiet, that is what the pressure feeling is for.
        RADIO_GAP_S = 15, -- control does not gabble
        RADIO_LOST = { -- eyes lost: the circle has started drifting
            'lost visual on %s. Last seen heading... somewhere.',
            'visual gone. The dot on your map is now an opinion.',
            'units describe %s as "there a second ago". Noted and logged.',
            'no eyes. He is officially a rumour with a postcode.',
        },
        RADIO_COLD = { -- the circle got so big it stopped being information
            'search area now covers most of the city. Calling it: we have lost %s.',
            'circle abandoned. Resume educated guessing.',
            '%s could be anywhere. He is definitely somewhere. That is all we have.',
            'trail is cold. Tea break at your own discretion, not mine.',
        },
        RADIO_FOUND = { -- back in contact after going fully cold
            'EYES ON %s. All units - and try to keep them this time.',
            'that is him. That is actually him. Go, go.',
            'contact re-established. Nobody put the last five minutes in the report.',
        },

        -- The escalation, narrated. A patrol relay is control reading someone
        -- else's sighting off a radio - it should never feel like the same
        -- thing as a copper actually looking at him.
        RADIO_RELAY = {
            'a unit has %s in sight. Not one of ours, but we will take it.',
            'patrol reports %s in the area. They will not stop him. You will.',
            'somebody with a radio can see %s. Move.',
        },
        RADIO_HELI_UP = {
            'air support is up and has %s. Twenty seconds. Do not waste them.',
            'eye in the sky, %s lit up. Go now, this will not last.',
        },
        RADIO_HELI_READY = {
            'we can get you air support. Somebody press the button.',
            'the helicopter is fuelled and the pilot is bored. Say the word.',
        },
        RADIO_WITNESS = {
            'member of the public phoned something in. Point on your map.',
            '999 call from a witness. No direction, just a postcode.',
            'someone saw something. They were not helpful about which way.',
            '999 from the public. Quote: "driving like an absolute knob". It is on your map.',
        },

        -- Another star on the board. Every one of them is a star he chose to
        -- earn by banking instead of running (pillar 4), and control knows it.
        RADIO_STARS = {
            'the board has given %s another star. He seems delighted. Stop him.',
            'star added. %s is officially a spree now, not an errand.',
            'upstairs would like it noted that %s is having a better night than we are.',
        },

        -- The cash-in-car paperwork, read like a logbook entry: the model,
        -- then the money. Said to the whole room - the sale is public, the
        -- WHERE is not (that stays acceptance test 9's business).
        CAR_LINES = {
            'He cashed a %s in somewhere. That is £%s of somebody else\'s car.',
            'Paperwork filed: one previously-loved %s, £%s. Condition: "was fine when I got in".',
            'A %s has just entered the second-hand economy at £%s. Its owner has entered a bus queue.',
        },

        -- The end-of-round paperwork: the take read out like an insurance
        -- write-off, and a superlative where one has been earned.
        STOCK_ITEMS = {
            'crisps', 'scratch cards', 'energy drinks',
            'lottery pens', 'phone chargers', 'novelty lighters',
        },
        PITIFUL_JOB_GBP  = 150, -- a completed job under this is a superlative
        GHOST_MIN_S      = 120, -- unseen this long in one stretch earns the ghost line
        NEVER_SEEN_LINE  = 'Not one confirmed sighting all round. The force would like a word with the force.',
        GHOST_LINE       = 'He was unaccounted for %d:%02d of it. Nobody is getting a commendation.',
        PETTY_SMASH_LINE = 'At some point he put a window through at %s for £%s. Magnificent.',
        PETTY_QUIET_LINE = 'He also tiptoed into %s and left with £%s. Worth it.',
    },

    -- ===== the map =====
    -- MADE-UP DEFAULTS, by owner's order. Nothing below has been tagged: on
    -- game night 2026-08-13, with a full server and an empty tag board,
    -- Darren overrode the never-guess rule for this block alone - quote, "if
    -- we don't have spawn points etc, make them up!" - so the mode could deal
    -- a round at all. Every entry is either a coordinate this repo has
    -- already verified somewhere else (marked chase/pint) or a canonical,
    -- widely documented spot, so expect the odd door that turns out to be a
    -- hedge. The rule itself still stands everywhere else in this repo.
    --
    -- Real tags from the tag board (https://sbm.dazrave.uk/tag) land here as
    -- data and replace these entries one for one; when the last default goes,
    -- DEFAULT_MAP and the round-start disclaimer go with it.
    --
    -- The shape (copy a line, fill in the numbers):
    locations = {
        -- Flips the one-line disclaimer at round start. Delete alongside the
        -- last made-up entry.
        DEFAULT_MAP = true,

        -- Where the robber starts, with a car. Spread so no spawn is next to
        -- more than two loot sites.
        --   { name = 'Legion car park', x = 0.0, y = 0.0, z = 0.0, h = 0.0 },
        --
        -- All three are well over a kilometre from every muster point, so
        -- whichever pair the session seed deals, the opening minute is his.
        robberSpawns = {
            { name = 'Vinewood Plaza',      x = 638.0,   y = 1.0,     z = 82.8,  h = 250.0 }, -- chase's Vinewood station kerb
            { name = 'Galileo Observatory', x = -436.0,  y = 1059.4,  z = 327.7, h = 130.0 }, -- pint, mission 1
            { name = 'LSIA apron',          x = -1336.0, y = -3044.0, z = 13.9,  h = 330.0 }, -- pint, mission 2 start
        },

        -- One muster point per round for the whole force. Spread so the
        -- opening 60 seconds isn't decided by geography.
        --   { name = 'Mission Row', x = 0.0, y = 0.0, z = 0.0, h = 0.0 },
        --
        -- Chase's city stations, verbatim - the same kerbs its fleet code has
        -- laid cars along all season.
        copSpawns = {
            { name = 'Mission Row',     x = 425.1,   y = -979.5,  z = 30.7, h = 90.0 },  -- chase
            { name = 'Vespucci station', x = -1108.0, y = -845.0,  z = 19.3, h = 40.0 },  -- chase
            { name = 'Davis sheriff station', x = 359.0, y = -1584.0, z = 29.3, h = 320.0 }, -- chase
        },

        -- Tier 1: convenience stores with glass frontage, so he can watch the
        -- street while the bag fills. Shell interiors only, no IPL loading.
        -- `tier` keys into Config.looting.tiers; `stock` overrides that tier's
        -- value for a site that is worth more or less than its neighbours.
        --   { name = 'Strawberry shop', tier = 'cornerShop', x = 0.0, y = 0.0, z = 0.0, h = 0.0 },
        --
        -- The first eight are the canonical robbable counters of central LS -
        -- half the FiveM robbery scripts ever written stand players on these
        -- exact tiles. The last four are coordinates this repo has already
        -- stood on (pint's fuel stops and mission targets), wearing shop hats.
        lootSites = {
            { name = "24/7, Innocence Blvd (Strawberry)",         x = 25.7,    y = -1347.3, z = 29.5,  h = 0.0 },
            { name = "24/7, Clinton Ave (Downtown Vinewood)",     x = 373.5,   y = 325.5,   z = 103.6, h = 0.0 },
            { name = "LTD, Grove St (Davis)",                     x = -47.9,   y = -1757.8, z = 29.4,  h = 0.0 },
            { name = "LTD, Mirror Park Blvd (Mirror Park)",       x = 1163.4,  y = -323.8,  z = 69.2,  h = 0.0 },
            { name = "LTD, Ginger St (Little Seoul)",             x = -707.5,  y = -914.3,  z = 19.2,  h = 0.0 },
            { name = "Rob's Liquor, El Rancho Blvd (Murrieta)",   x = 1135.8,  y = -982.3,  z = 46.4,  h = 0.0 },
            { name = "Rob's Liquor, San Andreas Ave (Vespucci)",  x = -1222.9, y = -907.0,  z = 12.3,  h = 0.0 },
            { name = "Rob's Liquor, Prosperity St (Morningwood)", x = -1487.6, y = -379.1,  z = 40.2,  h = 0.0 },
            { name = "Petrol shop, Davis",                        x = 180.6,   y = -1562.0, z = 29.3,  h = 0.0 }, -- pint fuel stop
            { name = "Petrol shop, La Puerta",                    x = -319.3,  y = -1471.7, z = 30.5,  h = 0.0 }, -- pint fuel stop
            { name = "Pier kiosk, Del Perro",                     x = -1850.1, y = -1231.8, z = 13.0,  h = 0.0 }, -- pint, the pier
            { name = "Hospital gift shop, Strawberry",            x = 341.3,   y = -1395.4, z = 32.5,  h = 0.0 }, -- pint, Central LS Medical
        },

        -- Unmarked doorways and alleys. Each one needs a blind approach where
        -- a corner breaks line of sight within ~30m of the door - that last
        -- property is the whole dive mechanic and will not survive being
        -- picked off a map.
        --   { name = 'Alta alley door', x = 0.0, y = 0.0, z = 0.0, h = 0.0 },
        --
        -- Doorways the story mode already proved you can stand in, spread one
        -- per district. The blind-approach property is EXACTLY what a made-up
        -- default cannot promise - these are the entries to replace first.
        safehouses = {
            { name = "Lester's gaff (Murrieta)",                x = 1273.9,  y = -1719.3, z = 54.9,  h = 25.0 },
            { name = "Auntie's porch (Forum Dr, Strawberry)",   x = -14.3,   y = -1441.5, z = 31.1,  h = 180.0 },
            { name = "Floyd's stairs (Vespucci)",               x = -1150.7, y = -1520.9, z = 10.6,  h = 120.0 },
            { name = "Alta St doorway (Downtown)",              x = -269.9,  y = -955.2,  z = 31.2,  h = 205.0 },
            { name = "Eclipse Towers side door (West Vinewood)", x = -773.2, y = 312.5,   z = 85.7,  h = 175.0 },
            { name = "Integrity Way lobby (Pillbox Hill)",      x = -47.5,   y = -590.0,  z = 37.9,  h = 250.0 },
            { name = "Grove St front room (Davis)",             x = 86.7,    y = -1959.4, z = 21.1,  h = 320.0 },
            { name = "Del Perro Heights (the nice flat)",       x = -1447.1, y = -538.3,  z = 34.7,  h = 35.0 },
            { name = "Whispymound Dr drive (Vinewood Hills)",   x = 7.9,     y = 548.1,   z = 175.6, h = 10.0 },
            { name = "The doorway opposite the nick (La Mesa)", x = 826.0,   y = -1290.0, z = 28.2,  h = 180.0 }, -- chase's La Mesa kerb
        },

        -- Where the air unit lands (/heli). Same made-up-defaults licence as
        -- the rest of this block. The Mission Row rooftop pad is the single
        -- most-documented helipad in the game - it is where the stock police
        -- mav lives. Not on the refusal list: no pad just means /heli says so.
        helipads = {
            { name = "Mission Row roof", x = 449.2, y = -981.2, z = 43.7, h = 90.0 },
        },
    },

    -- What the refusal message reads out, and what counts as enough. `min` is
    -- what the mode needs to deal a round at all; `want` is what the scope
    -- asks for once the map has been walked properly.
    locationNeeds = {
        { key = 'robberSpawns', min = 1, want = 3,  label = 'robber spawns',
          tag = "role 'player spawn', note 'robber spawn'" },
        { key = 'copSpawns',    min = 1, want = 3,  label = 'police muster points',
          tag = "role 'player spawn', note 'cop muster'" },
        { key = 'lootSites',    min = 3, want = 12, label = 'tier 1 loot sites (corner shops)',
          tag = "role 'shop / interaction'" },
        { key = 'safehouses',   min = 5, want = 10, label = 'safehouses',
          tag = "role 'safe zone'" },
    },
}
