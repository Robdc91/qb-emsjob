--[[
    qb-emsjob | server/revive.lua
    Validated revive / heal / checkup handling. Billing lives in billing.lua.
]]

local QBCore = exports['qb-core']:GetCoreObject()

local healCooldowns = {} -- [targetSource] = os.time() when cooldown ends

 ---------------------------------------------------------------------------
 -- Shared validation
 ---------------------------------------------------------------------------

--- Returns the target Player or nil; notifies `src` on any failure.
local function validateInteraction(src, targetId, needItem)
    targetId = tonumber(targetId)
    if not targetId or targetId == src then return nil end

    local Target = QBCore.Functions.GetPlayer(targetId)
    if not Target then return nil end

    -- Distance anti-cheat: both peds must be close on the server
    local srcPed = GetPlayerPed(src)
    local tgtPed = GetPlayerPed(targetId)
    if not tgtPed or tgtPed == 0 or not srcPed or srcPed == 0 then return nil end

    local dist = #(GetEntityCoords(srcPed) - GetEntityCoords(tgtPed))
    if dist > (Config.ReviveDistance + 5.0) then
        TriggerClientEvent('QBCore:Notify', src, _L('no_players_nearby'), 'error')
        return nil
    end

    if needItem then
        local EMSPlayer = QBCore.Functions.GetPlayer(src)
        if not EMSPlayer then return nil end
        local item = EMSPlayer.Functions.GetItemByName(needItem)
        if not item then
            TriggerClientEvent('QBCore:Notify', src, _L('no_item', { item = needItem }), 'error')
            return nil
        end
        EMSPlayer.Functions.RemoveItem(needItem, 1)
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[needItem], 'remove')
    end

    return Target
end

 ---------------------------------------------------------------------------
 -- Revive
 ---------------------------------------------------------------------------

RegisterNetEvent('qb-emsjob:server:RevivePlayer', function(targetId)
    local src = source

    local ok, reason = IsOnDutyEMS(src, Config.MinGradeToRevive)
    if not ok then
        if reason == 'not_ems' or reason == 'not_on_duty' then
            TriggerClientEvent('QBCore:Notify', src, _L('wrong_job'), 'error')
        else
            TriggerClientEvent('QBCore:Notify', src, _L('no_permission'), 'error')
        end
        return
    end

    local Target = validateInteraction(src, targetId, Config.ReviveItem)
    if not Target then return end

    local billed, insured = 0, false
    if Config.ChargeOnRevive then
        billed, insured = EMSBill(targetId, Config.RevivePrice, 'Medical treatment - revival')
    end

    TriggerClientEvent('qb-emsjob:client:Revived', targetId, billed)
    local msg = insured and _L('revived_by_insured', { name = GetPlayerName(targetId) })
        or _L('revived_by', { name = GetPlayerName(targetId), amount = billed })
    TriggerClientEvent('QBCore:Notify', src, msg, 'success')
end)

 ---------------------------------------------------------------------------
 -- Heal
 ---------------------------------------------------------------------------

RegisterNetEvent('qb-emsjob:server:HealPlayer', function(targetId)
    local src = source

    local ok, reason = IsOnDutyEMS(src, Config.MinGradeToHeal)
    if not ok then
        if reason == 'not_ems' or reason == 'not_on_duty' then
            TriggerClientEvent('QBCore:Notify', src, _L('wrong_job'), 'error')
        else
            TriggerClientEvent('QBCore:Notify', src, _L('no_permission'), 'error')
        end
        return
    end

    targetId = tonumber(targetId)
    if not targetId then return end

    -- Per-patient heal cooldown
    local now = os.time()
    if healCooldowns[targetId] and healCooldowns[targetId] > now then
        TriggerClientEvent('QBCore:Notify', src, _L('cooldown', { seconds = healCooldowns[targetId] - now }), 'error')
        return
    end

    local Target = validateInteraction(src, targetId, Config.HealItem)
    if not Target then return end

    healCooldowns[targetId] = now + Config.HealCooldownSeconds

    local billed, insured = 0, false
    if Config.ChargeOnHeal then
        billed, insured = EMSBill(targetId, Config.HealPrice, 'Medical treatment - first aid')
    end

    TriggerClientEvent('qb-emsjob:client:Healed', targetId, billed)
    local msg = insured and _L('healed_by_insured', { name = GetPlayerName(targetId) })
        or _L('healed_by', { name = GetPlayerName(targetId), amount = billed })
    TriggerClientEvent('QBCore:Notify', src, msg, 'success')
end)

 ---------------------------------------------------------------------------
 -- Checkup
 ---------------------------------------------------------------------------

RegisterNetEvent('qb-emsjob:server:CheckupPlayer', function(targetId)
    local src = source
    if not IsOnDutyEMS(src) then return end

    targetId = tonumber(targetId)
    if not targetId then return end

    local tgtPed = GetPlayerPed(targetId)
    if not tgtPed or tgtPed == 0 then return end

    local hp = GetEntityHealth(tgtPed)

    -- Insurance status is nice-to-have; never block vitals on it
    local insured = false
    local Target = QBCore.Functions.GetPlayer(targetId)
    if Target then
        local okHas, has = pcall(function()
            return exports['qb-emsjob']:HasInsurance(Target.PlayerData.citizenid)
        end)
        insured = okHas and has or false
    end

    TriggerClientEvent('qb-emsjob:client:SendVitals', src, hp, insured)
end)

AddEventHandler('playerDropped', function()
    healCooldowns[source] = nil
end)
