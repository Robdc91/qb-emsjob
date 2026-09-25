fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qb-emsjob'
description 'EMS/Paramedic job for QBCore: revive & heal players, ambulance garage, duty points, first-aid items'
author 'Buffy'
version '1.3.2'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

shared_scripts {
    'locale.lua',
    'locales/en.lua',
    'locales/es.lua',
    'config.lua',
}

client_scripts {
    -- NOTE: no @-includes for qb-target/PolyZone here. The @ syntax would
    -- execute their code a second time inside this resource; the exports
    -- (exports['qb-target']) work as long as qb-target is started first,
    -- which the dependencies block below enforces.
    'client/main.lua',
    'client/duty_menu.lua',
    'client/revive.lua',
    'client/garage.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/billing.lua',
    'server/revive.lua',
    'server/duty_menu.lua',
    'server/ems_alerts.lua',
    'server/items.lua',
}

dependencies {
    'qb-core',
    'qb-target',
    'PolyZone',
    'oxmysql',
}
