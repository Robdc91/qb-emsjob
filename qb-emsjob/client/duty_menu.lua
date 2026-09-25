--[[
    qb-emsjob | client/duty_menu.lua
    NUI duty menu controller: open/close, status presets, call-sign, roster.
]]

local QBCore = exports['qb-core']:GetCoreObject()

local menuOpen = false
local myStatus = nil     -- 'available' | 'busy' | 'outofservice'
local myCallsign = ''

 ---------------------------------------------------------------------------
 -- NUI helpers
 ---------------------------------------------------------------------------

local function sendNui(action, payload)
    SendNUIMessage({
        action = action,
        state = { onDuty = OnDuty, status = myStatus, callsign = myCallsign },
        roster = payload and payload.roster or nil,
    })
end

--- Request the roster from the server and forward it to the NUI when open.
function RefreshDutyRoster()
    if not menuOpen then return end
    QBCore.Functions.TriggerCallback('qb-emsjob:server:GetDutyRoster', function(roster)
        if menuOpen and roster then
            sendNui('roster', { roster = roster })
        end
    end)
end

 ---------------------------------------------------------------------------
 -- Open / close
 ---------------------------------------------------------------------------

function OpenDutyMenu()
    if menuOpen then return end
    if not IsEMS() then
        EMSNotify(_L('not_ems'), 'error')
        return
    end

    -- Restore persisted status from statebag (survives resource restarts)
    local st = LocalPlayer.state
    if st.emsStatus then myStatus = st.emsStatus end
    if st.emsCallsign then myCallsign = st.emsCallsign end

    menuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        state = { onDuty = OnDuty, status = myStatus, callsign = myCallsign },
    })
    RefreshDutyRoster()
end

local function CloseDutyMenu()
    if not menuOpen then return end
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

 ---------------------------------------------------------------------------
 -- NUI callbacks
 ---------------------------------------------------------------------------

RegisterNUICallback('close', function(_, cb)
    CloseDutyMenu()
    cb('ok')
end)

RegisterNUICallback('toggleDuty', function(_, cb)
    TriggerServerEvent('qb-emsjob:server:ToggleDuty')
    cb('ok')
end)

RegisterNUICallback('save', function(data, cb)
    cb('ok')

    local status = data and data.status or nil
    if status ~= nil and not Config.DutyStatuses[status] then
        EMSNotify(_L('status_invalid'), 'error')
        return
    end

    local callsign = data and data.callsign or ''
    callsign = tostring(callsign):upper():sub(1, Config.CallsignMaxLength)
    if callsign ~= '' and not callsign:match(Config.CallsignPattern) then
        EMSNotify(_L('callsign_invalid'), 'error')
        return
    end

    myStatus = status
    myCallsign = callsign

    LocalPlayer.state:set('emsStatus', myStatus, true)
    LocalPlayer.state:set('emsCallsign', myCallsign, true)

    TriggerServerEvent('qb-emsjob:server:SetDutyStatus', myStatus, myCallsign)
    EMSNotify(_L('status_saved'), 'success')
end)

 ---------------------------------------------------------------------------
 -- Server -> client sync
 ---------------------------------------------------------------------------

RegisterNetEvent('qb-emsjob:client:RosterUpdated', function(roster)
    if menuOpen and roster then
        sendNui('roster', { roster = roster })
    end
end)

-- Keep the NUI in sync when duty changes (handler also lives in main.lua)
RegisterNetEvent('QBCore:Client:SetDuty', function(duty)
    OnDuty = duty == true and IsEMS()
    if menuOpen then
        sendNui('state')
        RefreshDutyRoster()
    end
end)

 ---------------------------------------------------------------------------
 -- Cleanup
 ---------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if menuOpen then
        SetNuiFocus(false, false)
    end
end)
