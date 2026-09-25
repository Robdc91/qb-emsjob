fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qb-emsjob'
description 'EMS/Paramedic job for QBCore: revive & heal players, ambulance garage, duty points, first-aid items'
author 'Buffy'
version '1.4.7'

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
    'bridge.lua', -- shared optional-resource detection (must load first)
}

client_scripts {
    -- NOTE: no @-includes for qb-target/PolyZone here. The @ syntax would
    -- execute their code a second time inside this resource; the exports
    -- (via client/target_bridge.lua) work as long as the chosen target
    -- resource is started before this one.
    'client/main.lua',
    'client/target_bridge.lua',
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

-- qb-core is provided by real qb-core OR the qbx_core QB bridge, so this
-- resource runs on both classic QBCore and Qbox. qb-target/PolyZone are NOT
-- hard deps: the client target bridge uses qb-target when present and
-- ox_target otherwise (Config.UseTarget = false always works, 3D text).
dependencies {
    'qb-core',
    'oxmysql',
}
