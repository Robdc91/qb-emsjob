--[[
    qb-emsjob | server/items.lua
    Registers useable first-aid items (bandage, ifaks).

    Framework bridge: item existence is checked against ox_inventory when it
    is running (Qbox stacks route shared items there), falling back to
    QBCore.Shared.Items on classic QBCore.
]]

local QBCore = exports['qb-core']:GetCoreObject()

--- True when the item exists in the active inventory layer.
local function itemExists(item)
    if GetResourceState('ox_inventory') == 'started' then
        return exports.ox_inventory:Items(item) ~= nil
    end
    return QBCore.Shared.Items and QBCore.Shared.Items[item] ~= nil
end

local function registerUseable(item, eventName)
    if not itemExists(item) then
        print(('[qb-emsjob] Item "%s" not found in the inventory (ox_inventory or QBCore.Shared.Items) - useable item not registered.'):format(item))
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
