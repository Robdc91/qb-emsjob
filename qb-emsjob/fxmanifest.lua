fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qb-emsjob'
description 'EMS/Paramedic job for QBCore: revive & heal players, ambulance garage, duty points, first-aid items'
author 'Buffy'
version '1.3.0'

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
    '@PolyZone/client.lua',
    '@qb-target/init.lua',
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
