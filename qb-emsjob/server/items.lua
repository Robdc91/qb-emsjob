--[[
    qb-emsjob | server/items.lua
    Registers useable first-aid items (bandage, ifaks).
]]

local QBCore = exports['qb-core']:GetCoreObject()

local function registerUseable(item, eventName)
    if not QBCore.Shared.Items or not QBCore.Shared.Items[item] then
        print(('[qb-emsjob] Item "%s" not found in QBCore.Shared.Items - useable item not registered.'):format(item))
        return
    end
    QBCore.Functions.CreateUseableItem(item, function(source)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return end
        if not Player.Functions.GetItemByName(item) then return end
        TriggerClientEvent(eventName, source)
    end)
end

CreateThread(function()
    registerUseable(Config.HealItem, 'qb-emsjob:client:UseBandage')
    registerUseable(Config.ReviveItem, 'qb-emsjob:client:UseIfaks')
end)
