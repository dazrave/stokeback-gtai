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
    'client/main.lua',      -- state, roles, spawns, HUD (defines NickState & co)
    'client/police.lua',
    'client/robber.lua',
    'client/patrol.lua',    -- the AI, spawned on the robber's machine
    'client/gps.lua',       -- the one owner of the route line
}

-- Order matters only in that round.lua calls into the other three at runtime;
-- they share this resource's script environment through the Nick* globals
-- (a resource cannot call its own exports).
server_scripts {
    'server/session.lua',
    'server/detection.lua',
    'server/heist.lua',
    'server/escalation.lua',
    'server/round.lua',  -- owns the phase and the clock; publishes NickRound
    'server/orders.lua', -- everything the clients ask for, refereed
}

dependency 'core'
