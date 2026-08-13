fx_version 'cerulean'
game 'gta5'

name 'nick-of-time'
description 'Nick of Time - one robber, everyone else is police. Loot, stash, get out.'
author 'Stokeback Mountain'
version '0.1.0'

shared_scripts {
    '@core/shared/loadouts.lua',
    'config.lua',
}

client_scripts {
    '@core/client/lib.lua', -- FIRST: the SBM toolkit everything else uses
    'client/main.lua',
    'client/police.lua',
    'client/robber.lua',
}

-- Order matters only in that round.lua calls into the other three at runtime;
-- they share this resource's script environment through the Nick* globals
-- (a resource cannot call its own exports).
server_scripts {
    'server/session.lua',
    'server/detection.lua',
    'server/heist.lua',
    'server/round.lua',
}

dependency 'core'
