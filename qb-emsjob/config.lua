Config = {}

Config.JobName = 'ambulance'          -- QBCore job name players must have
Config.JobLabel = 'EMS'               -- label used in notifications
Config.MinGradeToRevive = 2           -- grade required to revive downed players
Config.MinGradeToHeal = 0             -- grade required to use the heal tool

-- Billing
Config.RevivePrice = 2500             -- billed to the revived player's bank
Config.HealPrice = 500                -- billed for a heal
Config.SocietyAccount = 'ambulance'   -- society account credited (qb-management)
Config.ChargeOnRevive = true          -- bill the player when revived
Config.ChargeOnHeal = true            -- bill the player when healed

-- Invoice mode
-- 'instant'   = money is taken immediately (legacy behavior)
-- 'invoices'  = a qb-phone invoice is created; patient can pay or contest it
Config.BillingMode = 'invoices'
Config.InvoiceSender = 'EMS'             -- shown as the invoice sender in qb-phone
Config.InvoiceSociety = Config.SocietyAccount

-- Insurance (optional)
-- Requires an insurance table: `player_insurance` (citizenid, expires, active).
-- See install/ems_billing.sql. Rows expire automatically by date.
Config.Insurance = {
    enabled = true,
    discount = 0.5,                      -- 50% off for insured players
    coversFull = false,                  -- true = insured patients pay nothing
}

-- Interaction
Config.UseTarget = true               -- qb-target zones (false = 3D text)
Config.ReviveDistance = 2.0           -- max distance for revive/heal options
Config.ReviveTime = 5000              -- ms progressbar time to revive someone
Config.HealTime = 3000                -- ms progressbar time to heal someone
Config.ReviveItem = 'ifaks'           -- item consumed per revive
Config.HealItem = 'bandage'           -- item consumed per heal
Config.HealCooldownSeconds = 30       -- cooldown between heals per patient
Config.SelfHealCooldownSeconds = 60   -- cooldown for personal first-aid items

-- Respawn / death
-- When a player self-respawns (or is revived), they are taken to the nearest hospital below.
-- 'beds' = actual bed coordinate, 'respawn' = outside waypoint used for the teleport.
Config.RespawnFee = 0                 -- optional self-respawn fee

Config.Hospitals = {
    {
        id = 'central',
        label = 'Central Los Santos Medical',
        blip = vec3(307.16, -600.33, 43.28),
        duty = {
            coords = vec3(307.16, -600.33, 43.28),
            length = 1.6, width = 1.6, heading = 0,
        },
        garage = {
            interact = vec3(312.94, -606.33, 43.28),
            spawn = vec4(317.55, -607.85, 43.39, 82.0),
            vehicles = { 'ambulance' },
            zone = { length = 6.0, width = 6.0, heading = 0 },
        },
        helipad = {
            enabled = true,
            interact = vec3(300.30, -585.00, 43.26),
            spawn = vec4(303.60, -578.60, 42.40, 250.0),
            vehicles = { 'policemav', 'annihilator2' },
        },
        respawn = vec4(295.83, -1446.96, 29.97, 225.0),
        beds = vec3(295.83, -1446.96, 29.97),
    },
    {
        id = 'sandy',
        label = 'Sandy Shores Medical',
        blip = vec3(1839.06, 3671.83, 34.25),
        duty = {
            coords = vec3(1839.06, 3671.83, 34.25),
            length = 1.6, width = 1.6, heading = 0,
        },
        garage = {
            interact = vec3(1841.53, 3672.66, 33.83),
            spawn = vec4(1846.29, 3670.99, 33.79, 180.0),
            vehicles = { 'ambulance' },
            zone = { length = 6.0, width = 6.0, heading = 0 },
        },
        helipad = {
            enabled = true,
            interact = vec3(1832.50, 3664.10, 33.90),
            spawn = vec4(1836.20, 3661.40, 34.10, 0.0),
            vehicles = { 'policemav', 'annihilator2' },
        },
        respawn = vec4(1838.71, 3673.99, 34.25, 90.0),
        beds = vec3(1838.71, 3673.99, 34.25),
    },
    {
        id = 'paleto',
        label = 'Paleto Bay Medical',
        blip = vec3(-246.04, 6331.23, 32.43),
        duty = {
            coords = vec3(-246.04, 6331.23, 32.43),
            length = 1.6, width = 1.6, heading = 0,
        },
        garage = {
            interact = vec3(-252.49, 6331.29, 42.41),
            spawn = vec4(-249.81, 6337.83, 42.42, 0.0),
            vehicles = { 'ambulance' },
            zone = { length = 6.0, width = 6.0, heading = 0 },
        },
        helipad = {
            enabled = false, -- set true to give Paleto a helipad too
            interact = vec3(-253.20, 6324.50, 42.42),
            spawn = vec4(-249.50, 6318.90, 42.42, 90.0),
            vehicles = { 'policemav' },
        },
        respawn = vec4(-246.04, 6331.23, 32.43, 270.0),
        beds = vec3(-246.04, 6331.23, 32.43),
    },
}

-- Duty menu (NUI)
Config.DutyStatuses = {                  -- valid status presets (10-codes)
    available = true,                    -- 10-8
    busy = true,                         -- 10-7
    outofservice = true,                 -- 10-23
}
Config.CallsignMaxLength = 8             -- e.g. "M-24"
Config.CallsignPattern = '^[A-Z0-9%-]+$' -- letters, digits and dashes only

-- Blips (hospital blips use Config.Hospitals[x].blip)
Config.EnableBlips = true
Config.BlipSprite = 61
Config.BlipColor = 1
Config.BlipScale = 0.75
Config.HeliBlip = { sprite = 422, color = 1, scale = 0.65 } -- EMS-only helipad blips

-- Last stand (downed but not dead) — mirrors qb-ambulancejob behavior
Config.LaststandEnabled = true
Config.LaststandTimer = 300           -- seconds a downed player bleeds out
Config.MinimumRevive = 5              -- minimum seconds the revive animation can be shortened to
Config.EmsNotification = true         -- alert on-duty EMS when a player goes down

-- Optional extras
Config.EnableCheckup = true           -- EMS can check a nearby player's health
Config.RemoveWeaponAfterDeath = false
Config.WeaponsToKeep = { 'WEAPON_UNARMED' }
