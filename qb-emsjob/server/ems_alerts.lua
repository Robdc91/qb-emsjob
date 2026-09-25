--[[
    qb-emsjob | server/ems_alerts.lua
    Relays downed-player alerts to all on-duty EMS players.
]]

local QBCore = exports['qb-core']:GetCoreObject()

RegisterNetEvent('qb-emsjob:server:PlayerDowned', function(coords)
    if not Config.EmsNotification then return end
    if type(coords) ~= 'vector3' and type(coords) ~= 'table' then return end

    local src = source
    local alertCoords = vector3(coords.x, coords.y, coords.z)

    for _, Player in pairs(QBCore.Functions.GetQBPlayers()) do
        local job = Player.PlayerData.job
        if job and job.name == Config.JobName and job.onduty and Player.PlayerData.source ~= src then
            TriggerClientEvent('qb-emsjob:client:DownedAlert', Player.PlayerData.source, alertCoords)
        end
    end
end)
