--[[
    qb-emsjob | server/main.lua
    Server core: QBCore object, duty toggle, grade helpers, spawn callback.
]]

local QBCore = exports['qb-core']:GetCoreObject()

 ---------------------------------------------------------------------------
 -- Helpers (globals shared across server files)
 ---------------------------------------------------------------------------

--- Validate the source is an on-duty EMS member with the required grade.
--- @param source number
--- @param minGrade number|nil
--- @return boolean ok
--- @return string|nil reason
function IsOnDutyEMS(source, minGrade)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false, 'no_player' end

    local job = Player.PlayerData.job
    if not job or job.name ~= Config.JobName then return false, 'not_ems' end
    if not job.onduty then return false, 'not_on_duty' end

    if minGrade and ((job.grade and job.grade.level) or 0) < minGrade then
        return false, 'no_permission'
    end

    return true, nil
end

function GetEMSPlayer(source)
    return QBCore.Functions.GetPlayer(source)
end

 ---------------------------------------------------------------------------
 -- Duty toggle (qb-core fires QBCore:Client:SetDuty, which the client handles)
 ---------------------------------------------------------------------------

RegisterNetEvent('qb-emsjob:server:ToggleDuty', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local job = Player.PlayerData.job
    if not job or job.name ~= Config.JobName then
        TriggerClientEvent('QBCore:Notify', src, _L('not_ems'), 'error')
        return
    end

    Player.Functions.SetJobDuty(not job.onduty)

    -- Duty state changed: push a fresh roster so the duty menu does not
    -- show stale on-duty flags. BroadcastDutyRoster is a global defined in
    -- server/duty_menu.lua (later in the load order; safe at event time).
    if BroadcastDutyRoster then BroadcastDutyRoster() end
end)

 ---------------------------------------------------------------------------
 -- Garage spawn permission callback
 ---------------------------------------------------------------------------

QBCore.Functions.CreateCallback('qb-emsjob:server:CanSpawnVehicle', function(source, cb)
    local ok = IsOnDutyEMS(source)
    cb(ok)
end)
