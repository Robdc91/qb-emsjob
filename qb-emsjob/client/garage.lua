--[[
    qb-emsjob | client/garage.lua
    Per-hospital EMS garages and helipads: take out / store ground vehicles and helicopters.
]]

local QBCore = exports['qb-core']:GetCoreObject()

local AMBULANCE_HASH = joaat('ambulance')
local FIRETRUK_HASH = joaat('firetruk')
local POLICEMAV_HASH = joaat('policemav')
local ANNIHILATOR2_HASH = joaat('annihilator2')

 ---------------------------------------------------------------------------
 -- Helpers
 ---------------------------------------------------------------------------

local function isEmergencyVehicle(veh)
    local model = GetEntityModel(veh)
    return GetVehicleClass(veh) == 18 or model == AMBULANCE_HASH or model == FIRETRUK_HASH
end

local function isEmergencyHeli(veh)
    local model = GetEntityModel(veh)
    return GetVehicleClass(veh) == 15 and (model == POLICEMAV_HASH or model == ANNIHILATOR2_HASH)
end

 ---------------------------------------------------------------------------
 -- Spawning / storing
 ---------------------------------------------------------------------------

local function takeOut(hospital, kind)
    local cfg = kind == 'helipad' and hospital.helipad or hospital.garage
    if not cfg or not cfg.vehicles or #cfg.vehicles == 0 then return end

    QBCore.Functions.TriggerCallback('qb-emsjob:server:CanSpawnVehicle', function(canSpawn)
        if not canSpawn then
            EMSNotify(_L('garage_busy'), 'error')
            return
        end

        -- Vehicle picker: qb-input on QBCore, ox_lib inputDialog on Qbox
        -- (ox_lib ships with qbx_core), first configured vehicle as fallback.
        local model = cfg.vehicles[1]
        if #cfg.vehicles > 1 then
            local function vehicleOptions()
                local opts = {}
                for _, m in ipairs(cfg.vehicles) do
                    opts[#opts + 1] = { value = m, text = m }
                end
                return opts
            end

            if GetResourceState('qb-input') == 'started' then
                local ok, input = pcall(function()
                    return exports['qb-input']:ShowInput({
                        header = hospital.label,
                        submitText = 'Take Out',
                        inputs = {
                            { text = 'Vehicle', name = 'vehicle', type = 'select', options = vehicleOptions() },
                        },
                    })
                end)
                if ok and input and input.vehicle then
                    model = input.vehicle
                end
            elseif GetResourceState('ox_lib') == 'started' then
                local ok, picked = pcall(function()
                    local entries = {}
                    for _, m in ipairs(cfg.vehicles) do
                        entries[#entries + 1] = { value = m, label = m }
                    end
                    local res = lib.inputDialog(hospital.label, {
                        { type = 'select', label = 'Vehicle', name = 'vehicle', options = entries, default = entries[1].value },
                    })
                    return res and res.vehicle
                end)
                if ok and picked then
                    model = picked
                end
            end
        end

        local spawn = cfg.spawn
        QBCore.Functions.SpawnVehicle(model, function(veh)
            SetEntityHeading(veh, spawn.w)
            SetVehicleNumberPlateText(veh, 'EMS' .. tostring(math.random(100, 999)))
            SetVehicleDirtLevel(veh, 0.0)
            SetVehicleEngineOn(veh, true, true, false)
            SetVehicleEngineHealth(veh, 1000.0)
            SetVehicleBodyHealth(veh, 1000.0)
            SetVehicleFuelLevel(veh, 100.0)
            if kind ~= 'helipad' then
                SetVehicleLivery(veh, 1)
            end
            TriggerEvent('vehiclekeys:client:SetOwner', QBCore.Functions.GetPlate(veh))
            TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
            EMSNotify(_L('vehicle_out'), 'success')
        end, spawn, true)
    end)
end

local function storeVehicle()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)

    if not veh or veh == 0 then
        EMSNotify(_L('not_in_ambulance'), 'error')
        return
    end

    local isHeli = isEmergencyHeli(veh)
    if not isEmergencyVehicle(veh) and not isHeli then
        EMSNotify(_L('not_in_ambulance'), 'error')
        return
    end

    DeleteVehicle(veh)
    EMSNotify(_L('vehicle_stored'), 'success')
end

 ---------------------------------------------------------------------------
 -- Zone setup
 ---------------------------------------------------------------------------

local zoneNames = {}

local function addGarageZone(hospital)
    local name = ('ems_garage_%s'):format(hospital.id)
    local g = hospital.garage
    TargetAddBoxZone(name, g.interact, g.zone.length or 6.0, g.zone.width or 6.0, {
        name = name,
        heading = g.zone.heading or 0,
        debugPoly = false,
        minZ = g.interact.z - 2.0,
        maxZ = g.interact.z + 1.5,
    }, {
        options = {
            {
                label = _L('target_garage'),
                icon = 'fas fa-truck-medical',
                job = Config.JobName,
                action = function() takeOut(hospital, 'garage') end,
            },
            {
                label = _L('target_store'),
                icon = 'fas fa-warehouse',
                job = Config.JobName,
                action = function() storeVehicle() end,
            },
        },
        distance = 3.0,
    })
    zoneNames[#zoneNames + 1] = name
end

local function addHelipadZone(hospital)
    local name = ('ems_heli_%s'):format(hospital.id)
    local hp = hospital.helipad
    TargetAddBoxZone(name, hp.interact, 8.0, 8.0, {
        name = name,
        heading = 0,
        debugPoly = false,
        minZ = hp.interact.z - 2.0,
        maxZ = hp.interact.z + 3.0,
    }, {
        options = {
            {
                label = _L('target_heli'),
                icon = 'fas fa-helicopter',
                job = Config.JobName,
                action = function() takeOut(hospital, 'helipad') end,
            },
            {
                label = _L('target_store'),
                icon = 'fas fa-warehouse',
                job = Config.JobName,
                action = function() storeVehicle() end,
            },
        },
        distance = 4.0,
    })
    zoneNames[#zoneNames + 1] = name
end

local function setupGarages()
    if Config.UseTarget then
        for _, h in ipairs(Config.Hospitals) do
            if h.garage then addGarageZone(h) end
            if h.helipad and h.helipad.enabled then addHelipadZone(h) end
        end
        return
    end

    -- 3D-text fallback: check every hospital spot each frame we are near one
    CreateThread(function()
        while true do
            local sleep = 1000
            if isLoggedIn and IsEMS() then
                local pos = GetEntityCoords(PlayerPedId())
                local nearSpot, kind, hospital = nil, nil, nil

                for _, h in ipairs(Config.Hospitals) do
                    if h.garage and #(pos - h.garage.interact) < 3.0 then
                        nearSpot, kind, hospital = h.garage.interact, 'garage', h
                    elseif h.helipad and h.helipad.enabled and #(pos - h.helipad.interact) < 5.0 then
                        nearSpot, kind, hospital = h.helipad.interact, 'helipad', h
                    end
                    if nearSpot then break end
                end

                if nearSpot then
                    sleep = 0
                    local inVeh = IsPedInAnyVehicle(PlayerPedId(), false)
                    local label = inVeh and _L('target_store') or (kind == 'helipad' and _L('target_heli') or _L('target_garage'))
                    DrawText3D(nearSpot.x, nearSpot.y, nearSpot.z + 0.5, label)
                    if IsControlJustReleased(0, 38) then -- E
                        if inVeh then
                            storeVehicle()
                        else
                            takeOut(hospital, kind)
                        end
                    end
                end
            end
            Wait(sleep)
        end
    end)
end

 ---------------------------------------------------------------------------
 -- Blips (EMS-only helipad markers)
 ---------------------------------------------------------------------------

local heliBlips = {}

local function refreshHeliBlips()
    local show = IsEMS() and OnDuty
    for _, blip in ipairs(heliBlips) do
        if DoesBlipExist(blip) then
            SetBlipAlpha(blip, show and 255 or 0)
        end
    end
end

CreateThread(function()
    if not Config.EnableBlips then return end
    for _, h in ipairs(Config.Hospitals) do
        if h.helipad and h.helipad.enabled then
            local blip = AddBlipForCoord(h.helipad.interact.x, h.helipad.interact.y, h.helipad.interact.z)
            SetBlipSprite(blip, Config.HeliBlip.sprite)
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, Config.HeliBlip.scale)
            SetBlipAsShortRange(blip, true)
            SetBlipColour(blip, Config.HeliBlip.color)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(h.label .. ' - Helipad')
            EndTextCommandSetBlipName(blip)
            SetBlipAlpha(blip, 0) -- hidden until on duty
            heliBlips[#heliBlips + 1] = blip
        end
    end
    refreshHeliBlips()
end)

RegisterNetEvent('QBCore:Client:SetDuty', function(duty)
    OnDuty = duty == true and IsEMS()
    refreshHeliBlips()
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(Job)
    PlayerJob = Job or {}
    OnDuty = PlayerJob.name == Config.JobName and PlayerJob.onduty == true
    refreshHeliBlips()
end)

 ---------------------------------------------------------------------------
 -- Lifecycle
 ---------------------------------------------------------------------------

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    setupGarages()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Config.UseTarget then
        for _, name in ipairs(zoneNames) do
            TargetRemoveZone(name)
        end
    end
    for _, blip in ipairs(heliBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
end)
