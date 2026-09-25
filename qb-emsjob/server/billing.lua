--[[
    qb-emsjob | server/billing.lua
    EMS billing: instant charges or qb-phone invoices (contestable), plus
    optional insurance discount via a `player_insurance` table.
]]

local QBCore = exports['qb-core']:GetCoreObject()

 ---------------------------------------------------------------------------
 -- Insurance
 ---------------------------------------------------------------------------

--- Returns true if the citizen currently holds valid insurance.
--- Auto-expires rows past their `expires` date.
local function HasInsurance(citizenid)
    if not Config.Insurance or not Config.Insurance.enabled then return false end

    local row = MySQL.single.await(
        'SELECT active, expires FROM player_insurance WHERE citizenid = ? LIMIT 1',
        { citizenid }
    )
    if not row or not row.active then return false end

    if row.expires then
        local expires = tostring(row.expires)
        local today = os.date('%Y-%m-%d')
        if expires < today then
            MySQL.update.await('UPDATE player_insurance SET active = ? WHERE citizenid = ?', { false, citizenid })
            return false
        end
    end

    return true
end

exports('HasInsurance', HasInsurance)

--- Apply insurance rules to a charge. Returns (finalAmount, insured).
local function ApplyInsurance(citizenid, amount)
    if not Config.Insurance or not Config.Insurance.enabled then
        return amount, false
    end

    if not HasInsurance(citizenid) then
        return amount, false
    end

    if Config.Insurance.coversFull then
        return 0, true
    end

    local discount = tonumber(Config.Insurance.discount) or 0.0
    if discount <= 0.0 then return amount, true end
    if discount >= 1.0 then return 0, true end

    return math.floor(amount * (1.0 - discount) + 0.5), true
end

 ---------------------------------------------------------------------------
 -- Instant billing (legacy mode)
 ---------------------------------------------------------------------------

local function chargeInstant(patientSource, amount)
    if not amount or amount <= 0 then return 0 end

    local Patient = QBCore.Functions.GetPlayer(patientSource)
    if not Patient then return 0 end

    local taken = 0
    if (Patient.PlayerData.money.bank or 0) >= amount then
        Patient.Functions.RemoveMoney('bank', amount, 'ems-billing')
        taken = amount
    elseif (Patient.PlayerData.money.cash or 0) >= amount then
        Patient.Functions.RemoveMoney('cash', amount, 'ems-billing')
        taken = amount
    else
        local bank = Patient.PlayerData.money.bank or 0
        if bank > 0 then
            Patient.Functions.RemoveMoney('bank', bank, 'ems-billing')
            taken = taken + bank
        end
    end

    if taken > 0 then
        pcall(function()
            TriggerEvent('qb-management:server:addSocietyMoney', Config.SocietyAccount, taken)
        end)
    end

    return taken
end

 ---------------------------------------------------------------------------
 -- Invoice billing (qb-phone style, contestable)
 ---------------------------------------------------------------------------

local function sendInvoice(patientSource, amount, reason)
    if not amount or amount <= 0 then return 0 end

    local Patient = QBCore.Functions.GetPlayer(patientSource)
    if not Patient then return 0 end

    local citizenid = Patient.PlayerData.citizenid

    -- qb-phone expects: target citizenid, sender citizenid, sender label, amount, (optional) society + invoice id
    local ok, err = pcall(function()
        TriggerEvent('qb-phone:server:sendInvoice', citizenid, "0", Config.InvoiceSender, amount, Config.InvoiceSociety, 0, reason)
    end)

    -- qb-phone accepts a source or citizenid in the first arg on most versions;
    -- fall back to inserting the row ourselves if the event is unavailable.
    if not ok then
        MySQL.insert.await(
            'INSERT INTO phone_invoices (citizenid, amount, society, sender, reason) VALUES (?, ?, ?, ?, ?)',
            { citizenid, amount, Config.InvoiceSociety or Config.SocietyAccount, Config.InvoiceSender, reason or 'Medical services' }
        )
        TriggerClientEvent('QBCore:Notify', patientSource, _L('invoice_received', { amount = amount }), 'primary', 6000)
    end

    return amount
end

 ---------------------------------------------------------------------------
 -- Public API
 ---------------------------------------------------------------------------

--- Bill a patient according to Config.BillingMode.
--- Returns what the EMS side should display as "billed".
--- @param patientSource number
--- @param baseAmount number
--- @param reason string
--- @return number billed, boolean insured
function EMSBill(patientSource, baseAmount, reason)
    local Patient = QBCore.Functions.GetPlayer(patientSource)
    if not Patient or not baseAmount or baseAmount <= 0 then return 0, false end

    local finalAmount, insured = ApplyInsurance(Patient.PlayerData.citizenid, baseAmount)
    if finalAmount <= 0 then
        return 0, insured
    end

    if Config.BillingMode == 'invoices' then
        sendInvoice(patientSource, finalAmount, reason)
        return finalAmount, insured
    end

    return chargeInstant(patientSource, finalAmount), insured
end

 ---------------------------------------------------------------------------
 -- Contest hook (works alongside qb-phone's own contest flow)
 ---------------------------------------------------------------------------

RegisterNetEvent('qb-emsjob:server:InvoiceContested', function(invoiceId, citizenid)
    local src = source

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.citizenid ~= citizenid then return end

    local jobLabel = 'EMS'
    local PlayerJob = Player.PlayerData.job
    if PlayerJob and PlayerJob.label then jobLabel = PlayerJob.label end

    -- Notify every on-duty EMS member that a charge was disputed
    for _, medic in pairs(QBCore.Functions.GetQBPlayers()) do
        local job = medic.PlayerData.job
        if job and job.name == Config.JobName and job.onduty then
            TriggerClientEvent('QBCore:Notify', medic.PlayerData.source, _L('invoice_contested', { id = invoiceId }), 'error', 7000)
        end
    end

    print(('[qb-emsjob] Invoice #%s contested by %s (%s)'):format(tostring(invoiceId), citizenid, jobLabel))
end)

 ---------------------------------------------------------------------------
 -- Self-respawn billing
 ---------------------------------------------------------------------------

RegisterNetEvent('qb-emsjob:server:RespawnBilled', function()
    local src = source
    local fee = Config.RespawnFee or 0
    if fee <= 0 then return end

    local billed, insured = EMSBill(src, fee, 'Hospital respawn fee')
    if billed > 0 then
        TriggerClientEvent('QBCore:Notify', src, _L('respawn_billed', { amount = billed }), 'primary')
    elseif insured then
        TriggerClientEvent('QBCore:Notify', src, _L('insurance_covered'), 'success')
    end
end)
