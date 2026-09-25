--[[
    qb-emsjob | client/main.lua
    Core client state, hospital blips, duty interactions and EMS downed-alerts.
    NOTE: globals defined here (IsEMS, IsOnDuty, EMSNotify, ProgressBar, ...)
    are shared with the other client files of this resource.
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- Shared client state (globals on purpose: used across client files)
isLoggedIn = isLoggedIn or false
OnDuty = OnDuty or false
PlayerJob = PlayerJob or {}

local resourceStarted = false

 ---------------------------------------------------------------------------
 -- Helpers (global)
 ---------------------------------------------------------------------------

function EMSNotify(msg, ntype, length)
    QBCore.Functions.Notify(msg, ntype or 'primary', length or 5000)
end

function IsEMS()
    return PlayerJob and PlayerJob.name == Config.JobName
end

function IsOnDuty()
    return OnDuty
end

function CanPerformEMS()
    return isLoggedIn and IsEMS() and OnDuty
end

exports('IsOnDuty', IsOnDuty)
exports('IsEMS', IsEMS)

function DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    local factor = #text / 370
    DrawRect(0.0, 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end

--- Small self-contained progress bar. Returns true when completed, false if cancelled (Backspace/Esc).
--- @param label string
--- @param duration number ms
--- @param animDict string|nil
--- @param animClip string|nil
function ProgressBar(label, duration, animDict, animClip)
    local finished, cancelled = false, false
    local ped = PlayerPedId()

    if animDict and animClip then
        RequestAnimDict(animDict)
        local timeout = GetGameTimer() + 3000
        while not HasAnimDictLoaded(animDict) and GetGameTimer() < timeout do Wait(10) end
        TaskPlayAnim(ped, animDict, animClip, 8.0, 8.0, -1, 1, 0, false, false, false)
    end

    CreateThread(function()
        local start = GetGameTimer()
        while GetGameTimer() - start < duration do
            Wait(0)
            DisableControlAction(0, 30, true) -- move left/right
            DisableControlAction(0, 31, true) -- move fwd/back
            DisableControlAction(0, 21, true) -- sprint
            DisableControlAction(0, 24, true) -- attack
            DisableControlAction(0, 25, true) -- aim
            DisableControlAction(0, 22, true) -- jump

            if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 200) then
                cancelled = true
                break
            end

            local progress = (GetGameTimer() - start) / duration
            -- background
            DrawRect(0.5, 0.925, 0.31, 0.04, 0, 0, 0, 160)
            -- fill
            DrawRect(0.5 - (0.3 * (1 - progress)) / 2, 0.925, 0.3 * progress, 0.033, 25, 132, 109, 220)
            -- label
            SetTextFont(4)
            SetTextScale(0.34, 0.34)
            SetTextCentre(true)
            SetTextColour(255, 255, 255, 255)
            SetTextEntry('STRING')
            AddTextComponentString(label)
            DrawText(0.5, 0.905)
        end
        finished = true
    end)

    while not finished do Wait(10) end

    StopAnimTask(ped, animDict or '', animClip or '', 1.0)
    return not cancelled
end

 ---------------------------------------------------------------------------
 -- Hospital blips
 ---------------------------------------------------------------------------

CreateThread(function()
    if not Config.EnableBlips then return end
    for _, h in ipairs(Config.Hospitals) do
        local blip = AddBlipForCoord(h.blip.x, h.blip.y, h.blip.z)
        SetBlipSprite(blip, Config.BlipSprite)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, Config.BlipScale)
        SetBlipAsShortRange(blip, true)
        SetBlipColour(blip, Config.BlipColor)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(h.label)
        EndTextCommandSetBlipName(blip)
    end
end)

 ---------------------------------------------------------------------------
 -- Duty state sync
 ---------------------------------------------------------------------------

local function refreshFromPlayerData(pd)
    if not pd then return end
    PlayerJob = pd.job or {}
    isLoggedIn = true
    OnDuty = PlayerJob.name == Config.JobName and PlayerJob.onduty == true
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    refreshFromPlayerData(QBCore.Functions.GetPlayerData())
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(Job)
    PlayerJob = Job or {}
    OnDuty = PlayerJob.name == Config.JobName and PlayerJob.onduty == true
end)

RegisterNetEvent('QBCore:Client:SetDuty', function(duty)
    OnDuty = duty == true and IsEMS()
    EMSNotify(OnDuty and _L('duty_on') or _L('duty_off'), OnDuty and 'success' or 'primary')
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    isLoggedIn = false
    OnDuty = false
    PlayerJob = {}
end)

 ---------------------------------------------------------------------------
 -- Duty interactions
 ---------------------------------------------------------------------------

local function toggleDuty()
    if not IsEMS() then
        EMSNotify(_L('not_ems'), 'error')
        return
    end
    TriggerServerEvent('qb-emsjob:server:ToggleDuty')
end

local function openDutyMenu()
    if not IsEMS() then
        EMSNotify(_L('not_ems'), 'error')
        return
    end
    OpenDutyMenu() -- defined in client/duty_menu.lua
end

local dutyZones = {}

local function setupDutyInteractions()
    if Config.UseTarget then
        for _, h in ipairs(Config.Hospitals) do
            local point = h.duty
            if point then
                local name = ('ems_duty_%s'):format(h.id)
                exports['qb-target']:AddBoxZone(name, point.coords, point.length, point.width, {
                    name = name,
                    heading = point.heading or 0,
                    debugPoly = false,
                    minZ = point.coords.z - 1.5,
                    maxZ = point.coords.z + 1.5,
                }, {
                    options = {
                        {
                            label = _L('target_menu'),
                            icon = 'fas fa-user-nurse',
                            job = Config.JobName,
                            action = function()
                                openDutyMenu()
                            end,
                        },
                    },
                    distance = 2.0,
                })
                dutyZones[#dutyZones + 1] = name
            end
        end
    else
        CreateThread(function()
            while true do
                local sleep = 1000
                if isLoggedIn and IsEMS() then
                    local pos = GetEntityCoords(PlayerPedId())
                    for _, h in ipairs(Config.Hospitals) do
                        local point = h.duty
                        if point then
                            local dist = #(pos - point.coords)
                            if dist < 10.0 then
                                sleep = 0
                                if dist < 1.5 then
                                    DrawText3D(point.coords.x, point.coords.y, point.coords.z + 0.5, _L('target_menu'))
                                    if IsControlJustReleased(0, 38) then -- E
                                        openDutyMenu()
                                    end
                                end
                            end
                        end
                    end
                end
                Wait(sleep)
            end
        end)
    end
end

 ---------------------------------------------------------------------------
 -- Downed-player alerts (blip + notification for on-duty EMS)
 ---------------------------------------------------------------------------

RegisterNetEvent('qb-emsjob:client:DownedAlert', function(coords)
    if not CanPerformEMS() or not coords then return end
    EMSNotify(_L('ems_alert'), 'error', 7500)

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 153)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 1.0)
    SetBlipFlashes(blip, true)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(_L('target_checkup'))
    EndTextCommandSetBlipName(blip)

    SetTimeout(60000, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)

 ---------------------------------------------------------------------------
 -- Lifecycle
 ---------------------------------------------------------------------------

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    if LocalPlayer.state.isLoggedIn then
        refreshFromPlayerData(QBCore.Functions.GetPlayerData())
    end
    setupDutyInteractions()
    resourceStarted = true
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Config.UseTarget then
        for _, name in ipairs(dutyZones) do
            exports['qb-target']:RemoveZone(name)
        end
    end
end)

-- NOTE: there is deliberately no client 'playerDropped' handler here -
-- that event only exists server-side. Local cleanup happens in
-- QBCore:Client:OnPlayerUnload above.
