fx_version 'cerulean'
game 'gta5'

name 'core'
description 'Stokeback core: the shared foundation every mode sits on. First job — keep the city alive.'
author 'Stokeback Mountain'
version '0.1.0'

shared_script 'shared/loadouts.lua'

client_scripts {
    'client/lib.lua',
    'client/world.lua',
    'client/clock.lua',
    'client/teams.lua',
    'client/hud.lua',
    'client/life.lua',
    'client/respawn.lua',
    'client/modifiers.lua',
    'client/spectator.lua',
    'client/vote.lua',
    'client/heat.lua',
}

server_scripts {
    'server/world.lua',
    'server/modes.lua',
    'server/teams.lua',
    'server/gametype.lua',
    'server/stats.lua',
    'server/rules.lua',
    'server/director.lua',
    'server/vote.lua',
    'server/heat.lua',
}

-- Modes load the toolkit into their own environment with
--   client_script '@core/client/lib.lua'
--   shared_script '@core/shared/loadouts.lua'
files {
    'client/lib.lua',
    'shared/loadouts.lua',
}
