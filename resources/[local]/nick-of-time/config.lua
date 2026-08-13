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
        SOFT_TRACK_GROWTH_MPS  = 12,   -- the search circle swells this fast
        SOFT_TRACK_COLD_RADIUS = 400,  -- past this the circle is useless: go cold

        HELI_PROXIMITY_ICON_RADIUS = 250, -- (wishlist) the piloted heli's icon

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
        BAND_MAX_MULTIPLIER      = 1.25,
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
    },

    -- ===== escalation =====
    -- Night one has no AI police at all (the descriptor says police = 'off'),
    -- so the stars are a number on the HUD and a reason the safehouse you just
    -- used is now on their map. The AI half of this block is the next build.
    escalation = {
        VALUE_PER_STAR             = 10000,
        AI_CARS_PER_STAR           = 1,    -- (wishlist)
        AI_CARS_MAX                = 6,    -- (wishlist)
        AI_RELAY_RADIUS            = 120,  -- (wishlist)
        BONUS_HELI_CONTACT_THRESH  = 0.15, -- (wishlist)
        BONUS_HELI_PING_S          = 20,   -- (wishlist)
        BONUS_HELI_USES_PER_ROUND  = 1,    -- (wishlist)
        ROADBLOCK_START_S          = 420,  -- (wishlist) 7:00
        ROADBLOCK_REQUIRES_PURSUIT = true, -- (wishlist)
        ROADBLOCK_MAP_WARNING_S    = 5,    -- (wishlist)

        -- (+) How long an alarm or a stash ping sits on the map before the
        -- trail it represents is stale enough to be a lie.
        PING_LIFE_MS = 45000,
    },

    -- ===== robber awareness =====
    -- He never gets to see the police on his map - he gets a feeling. Three
    -- states, delayed, so he is always reacting to something that was true a
    -- moment ago.
    pressure = {
        PRESSURE_RADIUS          = 400,
        PRESSURE_STATES          = 3,
        PRESSURE_UPDATE_DELAY_MS = 1500,
        PRESSURE_AI_CONTRIBUTION = 0.33, -- (wishlist) no AI to contribute yet
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
    -- not the evening.
    police = {
        RESPAWN_S = 15,
    },

    -- E to work / stash, G for the loud option and for calling it a day.
    controls = {
        PRIMARY   = 38, -- INPUT_PICKUP (E)
        SECONDARY = 47, -- INPUT_DETONATE (G)
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
    -- NOTHING IS TAGGED YET. Every one of these lists is empty on purpose:
    -- guessing a coordinate puts a car inside a building and a player in the
    -- sky, and this repo's hard rule is that map coordinates come from a
    -- person standing on the spot. They arrive from the tag board
    -- (https://sbm.dazrave.uk/tag) and land here as data.
    --
    -- Until then /nick start refuses with a list of what is still missing -
    -- the mode builds, deploys and sits there perfectly happily, it just
    -- cannot deal a round.
    --
    -- The shape, once tagged (copy the commented line, fill in the numbers):
    locations = {
        -- Where the robber starts, with a car. Spread so no spawn is next to
        -- more than two loot sites.
        --   { name = 'Legion car park', x = 0.0, y = 0.0, z = 0.0, h = 0.0 },
        robberSpawns = {},

        -- One muster point per round for the whole force. Spread so the
        -- opening 60 seconds isn't decided by geography.
        --   { name = 'Mission Row', x = 0.0, y = 0.0, z = 0.0, h = 0.0 },
        copSpawns = {},

        -- Tier 1: convenience stores with glass frontage, so he can watch the
        -- street while the bag fills. Shell interiors only, no IPL loading.
        -- `tier` keys into Config.looting.tiers; `stock` overrides that tier's
        -- value for a site that is worth more or less than its neighbours.
        --   { name = 'Strawberry shop', tier = 'cornerShop', x = 0.0, y = 0.0, z = 0.0, h = 0.0 },
        lootSites = {},

        -- Unmarked doorways and alleys. Each one needs a blind approach where
        -- a corner breaks line of sight within ~30m of the door - that last
        -- property is the whole dive mechanic and will not survive being
        -- picked off a map.
        --   { name = 'Alta alley door', x = 0.0, y = 0.0, z = 0.0, h = 0.0 },
        safehouses = {},
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
