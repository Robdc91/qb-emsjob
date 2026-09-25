--[[
    qb-emsjob | server/duty_menu.lua
    EMS roster: call-signs + duty statuses, broadcast to all EMS clients.
]]

local QBCore = exports['qb-core']:GetCoreObject()

local EMSRoster = {} -- [source] = { callsign = string, status = string|nil }

 ---------------------------------------------------------------------------
 -- Helpers
 ---------------------------------------------------------------------------

local function isEMSJob(job)
    return job and job.name == Config.JobName
end

--- Build the roster payload sent to clients. `forSource` marks the requesting player.
local function buildRoster(forSource)
    local roster = {}
    for _, Player in pairs(QBCore.Functions.GetQBPlayers()) do
        local job = Player.PlayerData.job
        if isEMSJob(job) then
            local src = Player.PlayerData.source
            local entry = EMSRoster[src]
            local charinfo = Player.PlayerData.charinfo or {}
            roster[#roster + 1] = {
                source = src,
                name = ('%s %s'):format(charinfo.firstname or '?', charinfo.lastname or ''),
                callsign = entry and entry.callsign or '',
                status = entry and entry.status or nil,
                onDuty = job.onduty == true,
                self = src == forSource,
            }
        end
    end
    table.sort(roster, function(a, b)
        if a.onDuty ~= b.onDuty then return a.onDuty end
        return a.callsign < b.callsign
    end)
    return roster
end

--- Push the current roster to every EMS player (on or off duty).
function BroadcastDutyRoster()
    for _, Player in pairs(QBCore.Functions.GetQBPlayers()) do
        if isEMSJob(Player.PlayerData.job) then
            local src = Player.PlayerData.source
            TriggerClientEvent('qb-emsjob:client:RosterUpdated', src, buildRoster(src))
        end
    end
end

 ---------------------------------------------------------------------------
 -- Events
 ---------------------------------------------------------------------------

RegisterNetEvent('qb-emsjob:server:SetDutyStatus', function(status, callsign)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not isEMSJob(Player.PlayerData.job) then return end

    -- Validate status (nil = clear)
    if status ~= nil and not Config.DutyStatuses[status] then return end

    -- Validate call-sign (empty string = clear)
    callsign = tostring(callsign or ''):upper():sub(1, Config.CallsignMaxLength)
    if callsign ~= '' and not callsign:match(Config.CallsignPattern) then return end

    EMSRoster[src] = { callsign = callsign, status = status }
    BroadcastDutyRoster()
end)

QBCore.Functions.CreateCallback('qb-emsjob:server:GetDutyRoster', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player or not isEMSJob(Player.PlayerData.job) then cb({}) return end
    cb(buildRoster(source))
end)

 ---------------------------------------------------------------------------
 -- Cleanup
 ---------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    local src = source
    if EMSRoster[src] then
        EMSRoster[src] = nil
        BroadcastDutyRoster()
    end
end)
