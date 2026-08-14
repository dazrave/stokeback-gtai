fx_version 'cerulean'
game 'gta5'

name 'the-stokeback-triathlon'
description 'The Stokeback Triathlon - run, ride, fly. Somebody organised a triathlon without checking what one is.'
author 'Stokeback Mountain'
version '0.1.0'

-- shared, not client-only: the server and every client have to flatten the
-- SAME course into the SAME ordered list of waypoints, or a checkpoint claim
-- means one thing on your screen and another on the server.
shared_scripts {
    'config.lua',
    'shared/course.lua',
}

client_scripts {
    '@core/client/lib.lua', -- FIRST: the SBM toolkit everything else uses
    'client/main.lua',
    'client/course.lua',
    'client/garage.lua',
    'client/banding.lua',
    'client/hud.lua',
}

-- race.lua first: round.lua calls into it at runtime through the TriRace
-- global (a resource cannot call its own exports).
server_scripts {
    'server/race.lua',
    'server/round.lua',
}

dependency 'core'
