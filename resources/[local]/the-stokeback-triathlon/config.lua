-- The Stokeback Triathlon. Run, then ride, then fly, in that order, because
-- somebody in Stoke organised a triathlon without checking what one is.
-- Every tunable lives here.
--
-- The KEY NAMES below are Rory's own, lifted out of the scope doc
-- (docs/modes/the-stokeback-triathlon.md) so a knob he wrote down is a knob he
-- can find with ctrl-F. Anything this file adds on top is marked (+); anything
-- the scope lists that night one does not read yet is marked (wishlist), so
-- nobody spends an evening tuning a number nothing uses.
Config = {

    -- ===== the round =====
    round = {
        ROUND_LENGTH_S    = 1200, -- 20:00 main time limit. A good race is ~15.
        FINISH_WINDOW_S   = 60,   -- once first place lands, this is everyone else's lot
        COUNTDOWN_S       = 10,   -- on the line, frozen, being talked at
        DNF_ON_WINDOW_END = true, -- still racing when the window shuts = DNF

        -- (+) Grace before the countdown starts. Racers are placed 1.5s after
        -- the round is set up and a client can spend another 2.5s waiting for
        -- collision to stream; a countdown started at setup was most of the
        -- way through before anyone could see the start line. Chase and nick
        -- both learned this the hard way.
        READY_S = 5,

        -- 1, not 3. A solo run is a time trial, which is exactly how you walk
        -- a freshly tagged course and find out that checkpoint 4 is inside a
        -- fence before six people are stood waiting.
        MIN_PLAYERS = 1,

        -- 'empty' by Darren's order (game night 2026-08-13): "no vehicles or
        -- police other than the ones for the race itself." The living city -
        -- the traffic, the pedestrians, the number 19 bus as part of the
        -- obstacle course - was the funniest knob in the file, and the owner
        -- has overruled it. Core does the rest: zero ambient density, no
        -- parked cars, no random patrol cops, and the heat system reads the
        -- empty city and stands its coppers down on top of POLICE below.
        POPULATION = 'empty',

        -- No NPC law. Nobody wants the final leg decided by a police
        -- helicopter taking an interest in six biplanes over Vinewood.
        POLICE = 'off',

        -- Late morning, clear, locked. The scope asks for conditions where
        -- the terrain and the aerial gates are clearly visible, and this is
        -- that: long sightlines, no fog to hide a gate in, sun high enough
        -- not to be directly in a pilot's eyes.
        CLOCK = { hour = 11, minute = 0, weather = 'EXTRASUNNY', freeze = true },
    },

    -- ===== the three disciplines =====
    -- Which legs, in which order. The whole leg system is data: a fourth
    -- discipline (the wishlist's "increasingly stupid definitions of
    -- triathlon") is an entry here plus a course table below, not new code.
    LEG_ORDER = { 'run', 'moto', 'air' },

    legs = {
        run = {
            LABEL           = 'OBSTACLE RUN',
            CHECKPOINT_WORD = 'checkpoint',
            RADIUS          = 4.0,  -- running checkpoint radius
            REQUIRE         = 'foot', -- on your own two feet or it does not count
            TARGET_S        = 60,   -- Darren's retiming: about a minute of running

            -- (+) Grounded legs snap their checkpoints to the terrain under
            -- the tagged x,y (Darren: "checkpoints other than air are on the
            -- ground, not floating"). The configured z is advisory: the
            -- client probes the ground for the ring and the claim, and the
            -- server measures grounded claims flat, so a made-up default z -
            -- or a tag taken at the wrong height - can never leave a
            -- checkpoint hanging in space or buried where nobody can claim it.
            GROUNDED        = true,
            BLIP_COLOUR     = 5,    -- yellow
            MARKER_TYPE     = 1,    -- cylinder on the deck
            MARKER_HEIGHT   = 2.0,
        },

        moto = {
            LABEL             = 'MOTOCROSS',
            CHECKPOINT_WORD   = 'checkpoint',
            RADIUS            = 12.0, -- motocross checkpoint radius
            TRANSITION_RADIUS = 6.0,  -- (+) arriving at the bikes, on foot
            TRANSITION_LABEL  = 'the bikes',
            REQUIRE           = 'vehicle',
            MODEL             = 'sanchez', -- one identical dirt bike for everyone
            TARGET_S          = 120,  -- Darren's retiming: two minutes on the bike
            GROUNDED          = true, -- (+) same terrain snap as the run
            BLIP_COLOUR       = 47,   -- orange
            MARKER_TYPE       = 1,
            MARKER_HEIGHT     = 4.0,
        },

        air = {
            LABEL             = 'BIPLANE',
            CHECKPOINT_WORD   = 'gate',
            RADIUS            = 45.0, -- plane gate radius: a gate you cannot hit is not a race
            TRANSITION_RADIUS = 8.0,  -- (+) arriving at the planes
            TRANSITION_LABEL  = 'the planes',
            REQUIRE           = 'vehicle',
            MODEL             = 'duster', -- the only actual biplane in the game
            TARGET_S          = 180,  -- Darren's retiming: three minutes in the air
            GROUNDED          = false, -- gates hang at their configured altitude by design
            BLIP_COLOUR       = 3,    -- blue
            MARKER_TYPE       = 28,   -- sphere, hanging in the air
            MARKER_HEIGHT     = 0.0,

            -- (+) Gates are meant to be tagged FROM THE COCKPIT: fly through
            -- the spot at the height you want the gate and tag it there, and
            -- the tag board records the altitude with it. If a gate got
            -- tagged from the ground instead, this lifts every one of them by
            -- the same amount rather than anybody editing a coordinate.
            GATE_HEIGHT_OFFSET = 0.0,
        },
    },

    -- ===== nobody is ever out of the race =====
    respawn = {
        DELAY_S            = 5,    -- respawn delay: a beat on the floor, then up
        PENALTY_S          = 0,    -- (+) extra seconds frozen at the checkpoint. 0 = no penalty
        AT_LAST_CHECKPOINT = true, -- back to the last thing you actually reached

        -- (+) A pilot who has already been through a gate is put back in the
        -- air with the engine running rather than parked on a hilltop - a
        -- crash that ends with a two minute climb back to altitude ends the
        -- race for that player anyway.
        AIR_RESPAWN_HEIGHT = 30.0, -- metres above the gate he last flew through
        AIR_RESPAWN_SPEED  = 55.0, -- m/s of forward speed so he is flying, not falling
    },

    vehicles = {
        REPLACE_DELAY_S = 3,   -- vehicle replacement delay
        SLOT_SPACING    = 6.0, -- (+) side by side across the transition, per racer
        AIR_SPACING     = 16.0, -- (+) planes need considerably more elbow room.
                                -- Trimmed from 22 when the line-up moved onto
                                -- a beach: still comfortably over a duster's
                                -- wingspan, and the shorter line keeps the far
                                -- bays on the flat sand instead of up the dune.
        RECOVER_COOLDOWN_S = 8, -- (+) rate limit on "my bike is in a lake"
    },

    -- ===== the rules of the thing =====
    rules = {
        -- Checkpoints in order, always. 'strict' is the only value night one
        -- implements: you cannot claim 5 while stood on 4.
        CHECKPOINT_ORDER = 'strict',

        -- How fussy the wrong-vehicle check is:
        --   'exact' - the configured bike/plane and nothing else
        --   'any'   - any vehicle at all will do
        --   'off'   - no check; run the moto leg on foot if you like
        -- Server-side, so it is a rule rather than a suggestion.
        VEHICLE_CHECK = 'exact',
        FOOT_CHECK    = true, -- run checkpoints do not count from a car

        -- (+) Latency allowance on the server's own distance check. The client
        -- decides you are in the ring; the server checks you are not claiming
        -- it from the next postcode.
        RADIUS_SLACK = 1.5,

        NO_WEAPONS        = true,  -- it is a sporting event
        PLAYER_COLLISION  = true,  -- deliberate and accidental crashes are the point
        INFINITE_STAMINA  = false, -- (+) off: a five minute run where everybody wheezes is the joke

        OUT_OF_BOUNDS_M = 0, -- (wishlist) 0 = off. Reset distance from the next checkpoint
    },

    controls = {
        RECOVER        = 47,  -- INPUT_DETONATE (G): "my bike is in a lake, send another"
        RECOVER_HOLD_S = 1.0, -- (+) held this long before it fires: a tap of G
                              -- mid-jump must never teleport anybody backwards
    },

    hud = {
        x = 0.5, y = 0.045, scale = 0.55,
        MARKER_DRAW_DISTANCE = 400.0, -- (+) beyond this the ring is not drawn, only blipped
        MARKER_ALPHA         = 120,

        -- (+) Sprite 1 is the plain dot and is the one sprite id that is
        -- always right. The prettier ones are a lucky dip of numbers and a
        -- wrong one draws nothing at all, which reads as a broken checkpoint.
        BLIP_SPRITE = 1,
        BLIP_SCALE  = 0.9,
    },

    -- ===== the steward =====
    -- (+) None of this changes the racing. It is a man with a clipboard who
    -- has opinions about your technique, which for this crowd is half the
    -- reason to turn up. %s takes a name unless noted.
    flavour = {
        BRIEFING = {
            'Three disciplines. Running, motocross, biplanes. No, that is not what a triathlon is. Yes, we are doing it anyway.',
            'Checkpoints in order. Skipping one does nothing except make you look keen.',
            'No weapons. This is a sporting event, and the insurance was very specific.',
            -- Take this line out when a real tagged course replaces the
            -- committee's made-up default in `courses` below.
            'Course by the committee: drawn up in the pub, walked by nobody. Tag your own at sbm.dazrave.uk/tag and it takes over.',
        },
        GO_LINE      = 'GO. Try to look like athletes.',

        -- (+) Shown while everyone is being placed and the real countdown has
        -- not been armed yet - without it the HUD briefly counted down from
        -- the provisional two minute placeholder, which read as a broken race.
        READY_LINE   = 'Hold. The steward is finding his whistle.',
        LEG_LINES    = { -- said to one racer as they start a leg. %d is the target, in minutes
            run  = 'On foot. About a minute if you are any good, which nobody here is.',
            moto = 'On the bike. Off-road, over the top, and please stop using the road.',
            air  = 'Into the plane. It is a biplane. It was the cheapest thing on the forecourt.',
        },
        WINNER_LINES = {
            '%s takes it. Sixty seconds for the rest of you, then I am packing up.',
            '%s wins the Stokeback Triathlon, an event that should not exist.',
            'That is %s. The trophy is a cup from the pub and it is already chipped.',
        },
        FINISH_LINES = { -- %s name, %d position
            [2] = '%s in second. So close, and yet a whole aeroplane away.',
            [3] = '%s third. Bronze. The medal nobody photographs.',
        },
        FINISH_DEFAULT = '%s finishes %s. Every finisher is a winner, which is a lie we tell finishers.',
        DNF_LINES = {
            '%s: did not finish. Officially. Spiritually, %s did not start.',
            '%s: DNF. Last seen arguing with a hillside.',
            '%s: DNF, and frankly the aircraft is the victim here.',
        },
        WROTE_OFF = { -- when somebody asks for a replacement vehicle
            '%s has written one off. There are more where that came from, sadly.',
            'Replacement dispatched to %s. The mechanic has stopped making eye contact.',
            '%s requires another one. The paperwork is becoming a second event.',
        },

        -- (+) Once somebody is properly getting through them, the steward
        -- stops pretending it is routine. %s name, %d which vehicle they are
        -- now on (the original counts as number one).
        WROTE_OFF_MANY = {
            AFTER = 3, -- from this many REPLACEMENTS, the lines below take over
            LINES = {
                '%s is on vehicle number %d. This is now a scrappage scheme with a finish line.',
                '%s has reached vehicle number %d. The insurers have stopped answering the phone.',
                '%s again. Number %d. The mechanic has asked to be reassigned to the running leg.',
            },
        },

        -- (+) The in-the-ring-in-the-wrong-thing help text, escalating: the
        -- longer you stand there, the less polite it gets. One list per
        -- offence, read top to bottom, sticking on the last line. %s is the
        -- required vehicle's model name where a line wants it.
        HECKLES = {
            EVERY_S = 3, -- seconds between nags (and between escalations)
            FOOT = {
                'This leg is on foot. Get out and run.',
                'Still in the vehicle. The judges have noticed.',
                'OUT. It is a RUNNING race. The clue is in the name.',
            },
            NEED_VEHICLE = {
                'Not on foot - you want the %s.',
                'The %s. The vehicle-shaped thing. Get on it.',
                'You cannot jog this leg. The %s exists for a reason.',
            },
            WRONG_VEHICLE = {
                'Wrong vehicle. It has to be the %s.',
                'That is still not a %s.',
                'The %s. The %s! It has your number painted on it and everything.',
            },
        },

        -- (+) A photo finish: anybody crossing within the margin of the
        -- finisher before them gets the full ceremony. Lines take (the one in
        -- front, the one behind, the gap in seconds).
        PHOTO = {
            MARGIN_S = 1.0,
            SHARD    = 'PHOTO FINISH',
            LINES    = {
                'Photo finish: %s edges %s by %.2f seconds. The photo is from a disposable camera.',
                'Photo finish: %s over %s by %.2f seconds. The stewards reviewed it in the pub.',
            },
        },

        -- (+) Split times, said out loud as each racer closes a discipline.
        -- %s name, %s the split as m:ss. The air split is the finish itself,
        -- so it has no line here.
        SPLITS = {
            ANNOUNCE = true,
            LINES = {
                run  = '%s off the run in %s. Now the motorbike bit.',
                moto = '%s through the dirt in %s. Now the sky, God help us.',
            },
        },

        -- (+) End-of-race discipline awards: fastest split per leg.
        -- %s name, %s the time.
        AWARDS = {
            run  = 'Fastest runner: %s, %s. A genuine athlete, regrettably.',
            moto = 'Fastest rider: %s, %s. The hills are pressing charges.',
            air  = 'Fastest pilot: %s, %s - three words nobody wanted to hear.',
        },

        -- (+) The steward's developing opinions about last place. Fires only
        -- once the race has been on a while AND the back marker is at least a
        -- whole discipline behind the front. Lines take (%s name, %s leg
        -- label lowercased, %d minutes since GO); use whichever they like.
        STRAGGLER = {
            AFTER_S     = 240, -- quiet for the first four minutes; everyone is trying
            EVERY_S     = 90,  -- then at most one remark per this
            LEGS_BEHIND = 1,   -- disciplines between front and back before it starts
            LINES = {
                '%s is still on the %s leg. The next vehicle has started to worry.',
                'Race control confirms %s remains on the %s leg, %d minutes in.',
                '%s: still the %s leg. The steward has sent out for a sandwich.',
            },
        },

        -- (+) The podium: gold, silver, bronze and a sponsor nobody has heard
        -- of, drawn on screen after the end card so it can be screenshotted
        -- rather than scrolling away in chat.
        PODIUM = {
            DELAY_S      = 6.5, -- let the end shard have its moment first
            SECONDS      = 12,
            TITLE        = 'THE STOKEBACK PODIUM',
            MEDALS       = {
                { label = 'GOLD',   tint = '~y~' },
                { label = 'SILVER', tint = '~w~' },
                { label = 'BRONZE', tint = '~o~' },
            },
            SPONSOR_LINE = 'Brought to you by %s.',
            SPONSORS = {
                'The Crown, Stoke (function room available)',
                "Barry's Bargain Aviation - no refunds",
                'Sanchez Parts & Salvage, incorporating Sanchez Parts',
                'The Fund for Distressed Biplanes',
                "Big Trev's Discount Helmets (probably fine)",
                'the concept of a triathlon, loosely',
            },
        },

        NOBODY_FINISHED = 'Twenty minutes and not one of you crossed the line. Standings by how far you got, then.',
        TIME_LINE       = 'Time. Pencils down.',
    },

    -- ===== the course =====
    -- MADE-UP DEFAULTS, ordered by Darren on game night 2026-08-13: "if we
    -- don't have spawn points etc, make them up!" That is an explicit owner
    -- override of the never-guess-a-coordinate rule (AGENTS.md), for this
    -- block only, so /tri start works tonight. The rule itself still stands:
    -- real tags from the tag board (https://sbm.dazrave.uk/tag, gametype
    -- 'the-stokeback-triathlon') land in these same tables and REPLACE this
    -- course, and the moment they do, nothing in here is guessed again.
    --
    -- Retimed on Darren's order, same night: about a minute of running, two
    -- minutes of motocross, three of biplanes - so the whole default course
    -- is now short and local to Paleto Bay. The Mount Chiliad summit
    -- crossing did not survive that arithmetic: a two-minute moto leg
    -- cannot contain a mountain. Rory's summit tag STAYS ON FILE for the
    -- real tagged course to route through later - it is (441.2, 5574.7,
    -- 793.4, h 93.5), the only real tag this mode has ever been given, and
    -- it deserves a course with room for it.
    --
    -- The guessing was done with the safety catch on. Grounded legs (see
    -- GROUNDED on the leg configs) snap to the terrain, so a z below is
    -- advisory; most ground points reuse pint-verified Paleto coordinates
    -- anyway. The air gates are invented outright, at 100-240m over the
    -- open water of the bay, where the 45m gate radius forgives everything
    -- except an actual crash.
    --
    -- The shape, once tagged (copy the commented line, fill in the numbers):
    --
    --   start        = { name = 'Start line',  x = 0.0, y = 0.0, z = 0.0, h = 0.0 },
    --   checkpoints  = { { name = 'run cp 1',  x = 0.0, y = 0.0, z = 0.0 }, ... }
    --   transition   = { name = 'The bikes',   x = 0.0, y = 0.0, z = 0.0, h = 0.0 },
    --   finish       = { name = 'Finish gate', x = 0.0, y = 0.0, z = 0.0 },
    --
    -- The heading (h) matters on the start line and on both transitions. It is
    -- the direction everything FACES: racers spread out across it centred on
    -- the start tag, and the bikes and planes are parked abreast starting AT
    -- the transition tag and running off to its right, one bay per racer. So a
    -- plane transition is tagged stood where the first plane should sit,
    -- looking straight down the runway. Checkpoints and gates need position
    -- only - you fly through a gate from whichever direction the course took
    -- you.
    courses = {
        default = {
            label = 'The Stokeback Original',

            -- Outside the Paleto pub, facing the sea. The same spot pint's
            -- water-landing regroup uses, so it is known open ground.
            start = { name = 'Start line - the Paleto pub', x = -292.0, y = 6256.0, z = 31.4, h = 0.0 },

            legs  = {
                -- ~585m, call it a minute and a bit of wheezing: up the
                -- street, along the beach road, down onto the sand. All
                -- pint-verified spots.
                run  = {
                    checkpoints = {
                        { name = 'run cp 1 - up the street',      x = -275.0, y = 6330.0, z = 32.0 },
                        { name = 'run cp 2 - beach road east',    x = -160.0, y = 6560.0, z = 31.0 },
                        { name = 'run cp 3 - down onto the sand', x = -260.0, y = 6720.0, z = 6.0 },
                    },
                },

                -- ~3.1km, about two minutes: west down the whole beach, up
                -- the dune at the far end, out to the coast highway by the
                -- Chiliad trailhead - the closest this leg now gets to the
                -- mountain it used to cross - back along the dune road, then
                -- west again to the planes, straight through the oncoming
                -- traffic of everyone still between cp 1 and cp 4.
                moto = {
                    transition = { name = 'The bikes - on the sand', x = -310.0, y = 6740.0, z = 4.0, h = 0.0 },
                    checkpoints = {
                        { name = 'moto cp 1 - down the beach',    x = -560.0,  y = 6690.0, z = 4.5 },
                        { name = 'moto cp 2 - more beach',        x = -790.0,  y = 6590.0, z = 6.0 },
                        { name = 'moto cp 3 - the far towel',     x = -1030.0, y = 6480.0, z = 5.0 },
                        { name = 'moto cp 4 - up the dune',       x = -1150.0, y = 6300.0, z = 20.0 },
                        { name = 'moto cp 5 - the trailhead',     x = -680.0,  y = 5990.0, z = 17.0 },
                        { name = 'moto cp 6 - the dune road',     x = -450.0,  y = 6560.0, z = 15.0 },
                    },
                },

                -- ~8km, about three minutes: the planes sit on the west
                -- beach pointing back east down a kilometre of flat sand,
                -- which is the runway, and nobody is to think about it too
                -- hard. Take off over the moto leg, climb out past Procopio
                -- Point, a great lap of the bay over open water, back in
                -- past Paleto Cove, and a red gate low over the beach to
                -- finish in front of everyone still running.
                air  = {
                    transition = { name = 'The planes - west end of the beach', x = -1350.0, y = 6370.0, z = 8.0, h = 295.0 },
                    checkpoints = {
                        { name = 'air gate 1 - climb-out over the water', x = -350.0,  y = 6900.0, z = 100.0 },
                        { name = 'air gate 2 - off Procopio Point',       x = 600.0,   y = 7300.0, z = 160.0 },
                        { name = 'air gate 3 - the far east turn',        x = 1500.0,  y = 7600.0, z = 220.0 },
                        { name = 'air gate 4 - the top of the lap',       x = 700.0,   y = 8000.0, z = 240.0 },
                        { name = 'air gate 5 - the long run west',        x = -800.0,  y = 7900.0, z = 220.0 },
                        { name = 'air gate 6 - the Paleto Cove turn',     x = -2200.0, y = 7350.0, z = 160.0 },
                        { name = 'air gate 7 - back in over the cove',    x = -1650.0, y = 6800.0, z = 100.0 },
                    },
                    finish = { name = 'Finish gate - low over the beach', x = -1150.0, y = 6470.0, z = 60.0 },
                },
            },
        },
    },

    -- Which course we are racing tonight. (wishlist) Multiple courses, and a
    -- vote to pick one, are a second entry in `courses` and a line in vote.lua.
    COURSE = 'default',

    -- What the refusal message reads out, and what counts as enough. `min` is
    -- what the mode needs to run a race at all; `want` is what the scope asks
    -- for once somebody has walked the whole course properly. `tag` is said
    -- verbatim to whoever is stood on the tag board with their phone out -
    -- the NOTE field is what this build reads, so the notes matter.
    courseNeeds = {
        { field = 'start', min = 1, want = 1,
          label = 'the start line',
          tag   = "role 'round start area', note 'start line' (heading = the way they face)" },

        { leg = 'run', field = 'checkpoints', min = 3, want = 8,
          label = 'obstacle run checkpoints',
          tag   = "role 'objective', notes 'run cp 1', 'run cp 2', ... in course order" },

        { leg = 'moto', field = 'transition', min = 1, want = 1,
          label = 'the motocross transition (where the bikes are)',
          tag   = "role 'vehicle spawn', note 'moto transition' - stand where the FIRST bike goes, facing the way they set off" },

        { leg = 'moto', field = 'checkpoints', min = 3, want = 8,
          label = 'motocross checkpoints',
          tag   = "role 'objective', notes 'moto cp 1', 'moto cp 2', ... - hills and dirt, not roads" },

        { leg = 'air', field = 'transition', min = 1, want = 1,
          label = 'the biplane transition (where the planes are)',
          tag   = "role 'vehicle spawn', note 'plane transition' - where the FIRST plane goes, facing straight down the runway" },

        { leg = 'air', field = 'checkpoints', min = 3, want = 7,
          label = 'aerial gates',
          tag   = "role 'objective', notes 'air cp 1', 'air cp 2', ... - tag these FROM THE PLANE, at gate height" },

        { leg = 'air', field = 'finish', min = 1, want = 1,
          label = 'the finish gate',
          tag   = "role 'extraction point', note 'finish gate' - also from the plane, at gate height" },
    },
}
