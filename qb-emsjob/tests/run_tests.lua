--[[
    qb-emsjob | tests/run_tests.lua
    Loads the REAL config.lua, locale.lua and the server modules under the
    stub environment, then unit-tests the server-side validation logic:

      - grade/duty/job checks + revive/heal distance & item validation
      - billing (instant vs invoices) + insurance + respawn fees
      - EMS alert relay (server/ems_alerts.lua)
      - duty roster sync (server/duty_menu.lua)
      - useable item registration (server/items.lua)
      - duty menu NUI controller (client/duty_menu.lua) via statebag + NUI stubs

    Run:  lua tests/run_tests.lua
]]

local stub = dofile('tests/fivem_stubs.lua')

 ---------------------------------------------------------------------------
 -- Tiny test framework
 ---------------------------------------------------------------------------

local tests = {}
local failed = 0

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

local function eq(actual, expected, msg)
    if actual ~= expected then
        error(('assertion failed%s: expected %s, got %s'):format(
            msg and (' (%s)'):format(msg) or '',
            tostring(expected), tostring(actual)), 2)
    end
end

local function isTrue(value, msg)
    if value ~= true then
        error(('assertion failed%s: expected true, got %s'):format(
            msg and (' (%s)'):format(msg) or '', tostring(value)), 2)
    end
end

 ---------------------------------------------------------------------------
 -- Load resource files (same global env, like FiveM shared/server scripts)
 ---------------------------------------------------------------------------

dofile('config.lua')
dofile('locale.lua')
dofile('locales/en.lua')
dofile('server/main.lua')
dofile('server/billing.lua')
dofile('server/revive.lua')
dofile('server/ems_alerts.lua')
dofile('server/duty_menu.lua')

-- items.lua registers at load time: only 'bandage' exists in Shared.Items,
-- so the 'ifaks' registration exercises the missing-item path in one load.
stub.QBCore.Shared.Items['bandage'] = { name = 'bandage', label = 'Bandage' }
dofile('server/items.lua')

-- Client side: client/main.lua defines the shared globals (IsEMS, OnDuty,
-- EMSNotify) that client/duty_menu.lua builds on. Its lifecycle handlers are
-- only registered here, never fired, and qb-target is not stubbed — so keep
-- Config.UseTarget = false to leave the 3D-text interaction thread inert.
-- Blips are disabled too: their CreateThread runs at load and the blip
-- natives are not stubbed.
Config.UseTarget = false
Config.EnableBlips = false
dofile('client/main.lua')
dofile('client/duty_menu.lua')

 ---------------------------------------------------------------------------
 -- Helpers
 ---------------------------------------------------------------------------

local V = stub.vector3

--- duty_menu.lua keeps a module-local EMSRoster; fire drop events so leftover
--- entries from earlier tests are cleared before stub.reset().
--- (Defined BEFORE setup(): a local declared after setup would leave setup
--- resolving clearRoster as a nil global at runtime.)
local function clearRoster()
    for src = 1, 5 do
        stub.fireEvent('playerDropped', src)
    end
end

--- Default scenario: medic(1) on duty grade 3 with items, patient(2) civilian.
local function setup()
    clearRoster()
    stub.reset()

    -- Self-heal config so a failing test can't poison later ones
    Config.BillingMode = 'invoices'
    Config.Insurance.enabled = true
    Config.Insurance.discount = 0.5
    Config.Insurance.coversFull = false
    Config.EmsNotification = true
    Config.RespawnFee = 0
    Config.UseTarget = false
    stub.localSource = 1

    -- Client scenario globals (client/main.lua): on-duty, logged-in medic.
    -- duty_menu.lua also keeps module-local menu state across tests, so
    -- force the menu closed for a clean start (no-op when already closed).
    OnDuty = true
    isLoggedIn = true
    stub.invokeNui('close')

    stub.addPlayer(1, {
        job = 'ambulance', grade = 3, onduty = true,
        bank = 5000, cash = 100,
        items = { ifaks = { amount = 10 }, bandage = { amount = 10 } },
        name = 'Medic Mike', citizenid = 'MED001',
    })
    stub.addPlayer(2, {
        job = 'unemployed', grade = 0, onduty = false,
        bank = 1000, cash = 50,
        name = 'Patient Pat', citizenid = 'PAT001',
    })

    -- 5m apart -> passes the (ReviveDistance + 5) server check
    stub.setPed(1, V(0, 0, 0), 200)
    stub.setPed(2, V(5, 0, 0), 200)
end

local function eventCount(name)
    local n = 0
    for _, e in ipairs(stub.eventLog) do
        if e.name == name then n = n + 1 end
    end
    return n
end

local function eventsTo(name, target)
    local n = 0
    for _, e in ipairs(stub.eventLog) do
        if e.name == name and e.target == target then n = n + 1 end
    end
    return n
end

local function lastRosterFor(target)
    local roster = nil
    for _, e in ipairs(stub.eventLog) do
        if e.name == 'qb-emsjob:client:RosterUpdated' and e.target == target then
            roster = e.args[1]
        end
    end
    return roster
end

 ---------------------------------------------------------------------------
 -- Grade / job / duty validation
 ---------------------------------------------------------------------------

test('IsOnDutyEMS: on-duty ambulance member passes', function()
    setup()
    local ok, reason = IsOnDutyEMS(1)
    isTrue(ok)
    eq(reason, nil)
end)

test('IsOnDutyEMS: off-duty EMS rejected as not_on_duty', function()
    setup()
    stub.players[1].PlayerData.job.onduty = false
    local ok, reason = IsOnDutyEMS(1)
    eq(ok, false)
    eq(reason, 'not_on_duty')
end)

test('IsOnDutyEMS: wrong job rejected as not_ems', function()
    setup()
    stub.players[1].PlayerData.job.name = 'mechanic'
    local ok, reason = IsOnDutyEMS(1)
    eq(ok, false)
    eq(reason, 'not_ems')
end)

test('IsOnDutyEMS: grade below requirement rejected', function()
    setup()
    local ok2, _ = IsOnDutyEMS(1, 2)   -- medic is grade 3 -> pass
    isTrue(ok2)
    local ok4, reason4 = IsOnDutyEMS(1, 4)
    eq(ok4, false)
    eq(reason4, 'no_permission')
end)

test('IsOnDutyEMS: unknown player rejected', function()
    setup()
    local ok, reason = IsOnDutyEMS(999)
    eq(ok, false)
    eq(reason, 'no_player')
end)

 ---------------------------------------------------------------------------
 -- Distance validation
 ---------------------------------------------------------------------------

test('revive within distance succeeds end-to-end', function()
    setup()
    stub.fireEvent('qb-emsjob:server:RevivePlayer', 1, 2)
    eq(eventCount('qb-emsjob:client:Revived'), 1)
    eq(stub.players[1].PlayerData.items.ifaks.amount, 9)
end)

test('revive too far away is rejected and item kept', function()
    setup()
    stub.setPed(2, V(500, 500, 0), 100) -- ~707m away
    stub.fireEvent('qb-emsjob:server:RevivePlayer', 1, 2)
    eq(eventCount('qb-emsjob:client:Revived'), 0)
    eq(stub.players[1].PlayerData.items.ifaks.amount, 10)
end)

test('reviving yourself is rejected', function()
    setup()
    stub.fireEvent('qb-emsjob:server:RevivePlayer', 1, 1)
    eq(eventCount('qb-emsjob:client:Revived'), 0)
end)

 ---------------------------------------------------------------------------
 -- validateInteraction: ambiguous / malformed target guards
 ---------------------------------------------------------------------------

test('revive rejects malformed target ids without consuming items', function()
    setup()
    stub.fireEvent('qb-emsjob:server:RevivePlayer', 1, 'grief-attempt')
    stub.fireEvent('qb-emsjob:server:RevivePlayer', 1, {})
    stub.fireEvent('qb-emsjob:server:RevivePlayer', 1)
    eq(eventCount('qb-emsjob:client:Revived'), 0)
    eq(stub.players[1].PlayerData.items.ifaks.amount, 10)

    -- numeric strings still coerce to a real target id
    stub.fireEvent('qb-emsjob:server:RevivePlayer', 1, '2')
    eq(eventsTo('qb-emsjob:client:Revived', 2), 1)
    eq(stub.players[1].PlayerData.items.ifaks.amount, 9)
end)

test('revive from an unregistered source is rejected', function()
    setup()
    stub.fireEvent('qb-emsjob:server:RevivePlayer', 999, 2)
    eq(eventCount('qb-emsjob:client:Revived'), 0)
    eq(eventsTo('qb-emsjob:client:Revived', 2), 0)
end)

 ---------------------------------------------------------------------------
 -- Item requirement
 ---------------------------------------------------------------------------

test('revive without required item is rejected', function()
    setup()
    stub.players[1].PlayerData.items.ifaks = nil
    stub.fireEvent('qb-emsjob:server:RevivePlayer', 1, 2)
    eq(eventCount('qb-emsjob:client:Revived'), 0)
end)

test('revive by off-duty medic is rejected', function()
    setup()
    stub.players[1].PlayerData.job.onduty = false
    stub.fireEvent('qb-emsjob:server:RevivePlayer', 1, 2)
    eq(eventCount('qb-emsjob:client:Revived'), 0)
end)

 ---------------------------------------------------------------------------
 -- Billing: instant mode
 ---------------------------------------------------------------------------

test('instant billing charges the patient bank and credits society', function()
    setup()
    Config.BillingMode = 'instant'
    Config.Insurance.enabled = false

    -- Patient has bank 1000 / cash 50: can't cover 2500, so the drain path
    -- takes what exists and returns the amount actually taken.
    local billed, insured = EMSBill(2, 2500, 'test revive')
    eq(billed, 1000)
    eq(insured, false)
    eq(stub.players[2].PlayerData.money.bank, 0)
    eq(stub.players[2].PlayerData.money.cash, 50) -- cash untouched by design
    eq(eventCount('qb-management:server:addSocietyMoney'), 1)

    Config.BillingMode = 'invoices'
    Config.Insurance.enabled = true
end)

test('instant billing takes the full amount when affordable', function()
    setup()
    Config.BillingMode = 'instant'
    Config.Insurance.enabled = false
    stub.players[2].PlayerData.money.bank = 5000

    local billed = EMSBill(2, 2500, 'affordable revive')
    eq(billed, 2500)
    eq(stub.players[2].PlayerData.money.bank, 2500)

    Config.BillingMode = 'invoices'
    Config.Insurance.enabled = true
end)

 ---------------------------------------------------------------------------
 -- Billing: society credit failure handling
 ---------------------------------------------------------------------------

test('instant billing completes even when the society credit event fails', function()
    setup()
    Config.BillingMode = 'instant'
    Config.Insurance.enabled = false
    stub.players[2].PlayerData.money.bank = 5000

    -- qb-management missing or restarting: the pcall around the credit must
    -- swallow the error, not abort the billing call mid-charge.
    local realTrigger = TriggerEvent
    TriggerEvent = function(name, ...)
        if name == 'qb-management:server:addSocietyMoney' then
            error('qb-management:server:addSocietyMoney unavailable')
        end
        return realTrigger(name, ...)
    end

    local billed = EMSBill(2, 2500, 'society credit failure')
    TriggerEvent = realTrigger -- restore before asserting

    eq(billed, 2500)
    eq(stub.players[2].PlayerData.money.bank, 2500)
end)

test('instant billing skips the society credit when nothing was taken', function()
    setup()
    Config.BillingMode = 'instant'
    Config.Insurance.enabled = false
    stub.players[2].PlayerData.money.bank = 0
    stub.players[2].PlayerData.money.cash = 0

    local billed = EMSBill(2, 2500, 'patient is broke')
    eq(billed, 0)
    eq(eventCount('qb-management:server:addSocietyMoney'), 0)
end)

test('instant billing falls back to cash when the bank is short', function()
    setup()
    Config.BillingMode = 'instant'
    Config.Insurance.enabled = false
    stub.players[2].PlayerData.money.bank = 0
    stub.players[2].PlayerData.money.cash = 3000

    local billed = EMSBill(2, 2500, 'cash fallback')
    eq(billed, 2500)
    eq(stub.players[2].PlayerData.money.cash, 500)
    eq(stub.players[2].PlayerData.money.bank, 0)
    eq(eventCount('qb-management:server:addSocietyMoney'), 1)
end)

 ---------------------------------------------------------------------------
 -- Billing: invoice mode (qb-phone style)
 ---------------------------------------------------------------------------

test('invoice mode sends a phone invoice and takes no money', function()
    setup()
    Config.BillingMode = 'invoices'
    Config.Insurance.enabled = false

    local billed = EMSBill(2, 2500, 'test invoice')
    eq(billed, 2500)
    eq(stub.players[2].PlayerData.money.bank, 1000) -- untouched
    eq(eventCount('qb-phone:server:sendInvoice'), 1)

    Config.Insurance.enabled = true
end)

 ---------------------------------------------------------------------------
 -- Insurance
 ---------------------------------------------------------------------------

local HasInsurance = function(cid)
    return stub.resourceExports['qb-emsjob'].HasInsurance(cid)
end

test('insurance: no row means uninsured', function()
    setup()
    eq(HasInsurance('PAT001'), false)
end)

test('insurance: active row passes', function()
    setup()
    stub.db.insurance['PAT001'] = { active = true, expires = '2099-01-01' }
    eq(HasInsurance('PAT001'), true)
end)

test('insurance: expired row is auto-invalidated', function()
    setup()
    stub.db.insurance['PAT001'] = { active = true, expires = '2020-01-01' }
    eq(HasInsurance('PAT001'), false)
    eq(stub.db.insurance['PAT001'].active, false)
end)

test('insurance: 50% discount halves the invoice', function()
    setup()
    Config.Insurance.enabled = true
    Config.Insurance.discount = 0.5
    Config.Insurance.coversFull = false
    stub.db.insurance['PAT001'] = { active = true, expires = '2099-01-01' }

    local billed, insured = EMSBill(2, 2500, 'insured revive')
    eq(billed, 1250)
    eq(insured, true)
    eq(eventCount('qb-phone:server:sendInvoice'), 1)
end)

test('insurance: coversFull zeroes the charge', function()
    setup()
    Config.Insurance.coversFull = true
    stub.db.insurance['PAT001'] = { active = true, expires = '2099-01-01' }

    local billed, insured = EMSBill(2, 2500, 'fully covered')
    eq(billed, 0)
    eq(insured, true)
    eq(eventCount('qb-phone:server:sendInvoice'), 0)

    Config.Insurance.coversFull = false
end)

 ---------------------------------------------------------------------------
 -- Respawn fee billing (qb-emsjob:server:RespawnBilled)
 ---------------------------------------------------------------------------

local lastNotifyTo = function(target)
    for _, e in ipairs(stub.eventLog) do
        if e.name == 'QBCore:Notify' and e.target == target then
            return e.args[1]
        end
    end
    return nil
end

test('respawn fee is billed to the patient', function()
    setup()
    Config.RespawnFee = 800
    Config.BillingMode = 'instant'
    Config.Insurance.enabled = false
    stub.players[2].PlayerData.money.bank = 5000

    stub.fireEvent('qb-emsjob:server:RespawnBilled', 2)

    eq(stub.players[2].PlayerData.money.bank, 4200)
    isTrue(lastNotifyTo(2):find('800', 1, true) ~= nil, 'fee notify mentions the amount')
end)

test('respawn fee is skipped when disabled', function()
    setup()
    Config.RespawnFee = 0

    stub.fireEvent('qb-emsjob:server:RespawnBilled', 2)

    eq(stub.players[2].PlayerData.money.bank, 1000)
    eq(eventCount('QBCore:Notify'), 0)
end)

test('respawn fee announces insurance coverage when nothing is charged', function()
    setup()
    Config.RespawnFee = 800
    Config.Insurance.coversFull = true
    stub.db.insurance['PAT001'] = { active = true, expires = '2099-01-01' }

    stub.fireEvent('qb-emsjob:server:RespawnBilled', 2)

    eq(stub.players[2].PlayerData.money.bank, 1000)
    eq(eventCount('qb-phone:server:sendInvoice'), 0)
    isTrue(lastNotifyTo(2):find('insurance covered', 1, true) ~= nil, 'insurance-covered notify')
end)

 ---------------------------------------------------------------------------
 -- Heal cooldown
 ---------------------------------------------------------------------------

test('second heal inside cooldown is rejected', function()
    setup()
    stub.fireEvent('qb-emsjob:server:HealPlayer', 1, 2)
    eq(eventCount('qb-emsjob:client:Healed'), 1)
    stub.fireEvent('qb-emsjob:server:HealPlayer', 1, 2)
    eq(eventCount('qb-emsjob:client:Healed'), 1) -- still 1
end)

 ---------------------------------------------------------------------------
 -- Garage callback
 ---------------------------------------------------------------------------

test('garage callback allows on-duty EMS', function()
    setup()
    local result = nil
    stub.callbacks['qb-emsjob:server:CanSpawnVehicle'](1, function(ok) result = ok end)
    eq(result, true)
end)

test('garage callback rejects off-duty players', function()
    setup()
    stub.players[1].PlayerData.job.onduty = false
    local result = nil
    stub.callbacks['qb-emsjob:server:CanSpawnVehicle'](1, function(ok) result = ok end)
    eq(result, false)
end)

 ---------------------------------------------------------------------------
 -- Duty toggle
 ---------------------------------------------------------------------------

test('duty toggle flips onduty for EMS', function()
    setup()
    stub.players[1].PlayerData.job.onduty = false
    stub.fireEvent('qb-emsjob:server:ToggleDuty', 1)
    eq(stub.players[1].PlayerData.job.onduty, true)
end)

 ---------------------------------------------------------------------------
 -- Invoice contest hook
 ---------------------------------------------------------------------------

test('contested invoice notifies on-duty EMS', function()
    setup()
    stub.fireEvent('qb-emsjob:server:InvoiceContested', 2, 42, 'PAT001')
    isTrue(eventCount('QBCore:Notify') >= 1)
end)

test('contest with mismatched citizenid is ignored', function()
    setup()
    stub.fireEvent('qb-emsjob:server:InvoiceContested', 2, 42, 'SOMEONEELSE')
    eq(eventCount('QBCore:Notify'), 0)
end)

 ---------------------------------------------------------------------------
 -- EMS alert relay (server/ems_alerts.lua)
 ---------------------------------------------------------------------------

test('downed alert relays to on-duty EMS only, excluding the victim', function()
    setup()
    -- second medic, also on duty
    stub.addPlayer(3, { job = 'ambulance', grade = 1, onduty = true, name = 'Medic Amy', citizenid = 'MED002' })

    stub.fireEvent('qb-emsjob:server:PlayerDowned', 2, V(100, 200, 30))

    -- both medics get the alert...
    eq(eventsTo('qb-emsjob:client:DownedAlert', 1), 1)
    eq(eventsTo('qb-emsjob:client:DownedAlert', 3), 1)
    -- ...but the downed civilian does not
    eq(eventsTo('qb-emsjob:client:DownedAlert', 2), 0)
end)

test('downed alert is suppressed when notifications are disabled', function()
    setup()
    Config.EmsNotification = false
    stub.fireEvent('qb-emsjob:server:PlayerDowned', 2, V(100, 200, 30))
    eq(eventsTo('qb-emsjob:client:DownedAlert', 1), 0)
    Config.EmsNotification = true
end)

test('downed alert rejects garbage coords', function()
    setup()
    stub.fireEvent('qb-emsjob:server:PlayerDowned', 2, 'not-a-vector')
    stub.fireEvent('qb-emsjob:server:PlayerDowned', 2, nil)
    eq(eventsTo('qb-emsjob:client:DownedAlert', 1), 0)
end)

test('downed alert is broadcast with a proper vector3', function()
    setup()
    stub.fireEvent('qb-emsjob:server:PlayerDowned', 2, V(10, 20, 30))
    local found = nil
    for _, e in ipairs(stub.eventLog) do
        if e.name == 'qb-emsjob:client:DownedAlert' and e.target == 1 then found = e.args[1] end
    end
    isTrue(found ~= nil)
    eq(found.x, 10.0)
    eq(found.y, 20.0)
    eq(found.z, 30.0)
end)

test('off-duty medics do not receive downed alerts', function()
    setup()
    stub.players[1].PlayerData.job.onduty = false
    stub.fireEvent('qb-emsjob:server:PlayerDowned', 2, V(1, 2, 3))
    eq(eventsTo('qb-emsjob:client:DownedAlert', 1), 0)
end)

 ---------------------------------------------------------------------------
 -- Duty roster sync (server/duty_menu.lua)
 ---------------------------------------------------------------------------

test('SetDutyStatus stores callsign and status for EMS', function()
    setup()
    stub.fireEvent('qb-emsjob:server:SetDutyStatus', 1, 'busy', 'M-24')

    local roster = lastRosterFor(1)
    isTrue(roster ~= nil, 'roster broadcast received')
    isTrue(#roster >= 1)
    local me = roster[1]
    eq(me.source, 1)
    eq(me.callsign, 'M-24')
    eq(me.status, 'busy')
    eq(me.self, true)
    eq(me.name, 'John Doe') -- from stub charinfo
end)

test('SetDutyStatus lowercases input to uppercase callsigns', function()
    setup()
    stub.fireEvent('qb-emsjob:server:SetDutyStatus', 1, 'available', 'm-7')
    local roster = lastRosterFor(1)
    eq(roster[1].callsign, 'M-7')
end)

test('SetDutyStatus rejects invalid status', function()
    setup()
    stub.fireEvent('qb-emsjob:server:SetDutyStatus', 1, 'raid-boss', 'M-24')
    eq(eventsTo('qb-emsjob:client:RosterUpdated', 1), 0)
end)

test('SetDutyStatus rejects callsigns with illegal characters', function()
    setup()
    stub.fireEvent('qb-emsjob:server:SetDutyStatus', 1, 'available', 'M-24<script>')
    eq(eventsTo('qb-emsjob:client:RosterUpdated', 1), 0)
end)

test('SetDutyStatus truncates overlong callsigns to the configured max', function()
    setup()
    stub.fireEvent('qb-emsjob:server:SetDutyStatus', 1, 'available', 'M-24-ALPHA-ECHO')
    local roster = lastRosterFor(1)
    eq(roster[1].callsign, 'M-24-ALP') -- CallsignMaxLength = 8
end)

test('SetDutyStatus is rejected for non-EMS players', function()
    setup()
    stub.fireEvent('qb-emsjob:server:SetDutyStatus', 2, 'available', 'CIV-1')
    eq(eventsTo('qb-emsjob:client:RosterUpdated', 2), 0)
end)

test('GetDutyRoster callback returns roster with self flag for non-EMS too', function()
    setup()
    local result
    stub.callbacks['qb-emsjob:server:GetDutyRoster'](2, function(r) result = r end)
    eq(#result, 0) -- civilian gets an empty roster

    stub.fireEvent('qb-emsjob:server:SetDutyStatus', 1, 'available', 'M-1')
    stub.callbacks['qb-emsjob:server:GetDutyRoster'](1, function(r) result = r end)
    eq(result[1].callsign, 'M-1')
    eq(result[1].self, true)
end)

test('playerDropped clears roster entry and rebroadcasts', function()
    setup()
    stub.addPlayer(3, { job = 'ambulance', grade = 1, onduty = true, name = 'Medic Amy', citizenid = 'MED002' })
    stub.fireEvent('qb-emsjob:server:SetDutyStatus', 1, 'busy', 'M-24')
    stub.fireEvent('qb-emsjob:server:SetDutyStatus', 3, 'busy', 'M-25')

    -- FiveM removes the player object when they drop
    stub.players[3] = nil
    stub.fireEvent('playerDropped', 3)

    local roster = lastRosterFor(1)
    isTrue(#roster == 1, 'dropped medic removed from roster')
    eq(roster[1].callsign, 'M-24')
end)

 ---------------------------------------------------------------------------
 -- Useable item registration (server/items.lua)
 ---------------------------------------------------------------------------

test('bandage is registered as a useable item', function()
    setup()
    isTrue(stub.useableItems['bandage'] ~= nil)
end)

test('missing shared item is not registered (ifaks path)', function()
    setup()
    -- items.lua was loaded with only 'bandage' in Shared.Items, so the
    -- missing-ifaks registration path already ran; assert the consequence.
    isTrue(stub.useableItems['ifaks'] == nil)
end)

test('using bandage fires the client event only when the player has it', function()
    setup()
    local fn = stub.useableItems['bandage']
    isTrue(fn ~= nil)

    -- medic has bandages -> event fires
    fn(1)
    eq(eventsTo('qb-emsjob:client:UseBandage', 1), 1)

    -- patient has none -> no event
    fn(2)
    eq(eventsTo('qb-emsjob:client:UseBandage', 2), 0)

    -- unknown source -> no event, no crash
    fn(999)
    eq(eventsTo('qb-emsjob:client:UseBandage', 999), 0)
end)

 ---------------------------------------------------------------------------
 -- Duty menu controller (client/duty_menu.lua)
 ---------------------------------------------------------------------------

local function lastNui(action)
    local found = nil
    for _, m in ipairs(stub.nuiMessages) do
        if m.action == action then found = m end
    end
    return found
end

local function nuiCount(action)
    local n = 0
    for _, m in ipairs(stub.nuiMessages) do
        if m.action == action then n = n + 1 end
    end
    return n
end

--- Server-side SetDutyStatus for src, as the roster flow would.
local function setStatus(src, status, callsign)
    stub.fireEvent('qb-emsjob:server:SetDutyStatus', src, status, callsign)
end

test('duty menu: open is gated to EMS players', function()
    setup()
    stub.players[1].PlayerData.job.name = 'mechanic'
    OpenDutyMenu()
    eq(nuiCount('open'), 0)
    eq(stub.nuiFocus.focused, false)

    stub.players[1].PlayerData.job.name = 'ambulance'
    OpenDutyMenu()
    eq(nuiCount('open'), 1)
    eq(stub.nuiFocus.focused, true)
end)

test('duty menu: off-duty EMS still opens the menu', function()
    setup()
    stub.players[1].PlayerData.job.onduty = false
    OnDuty = false -- mirror the client-side duty flag
    OpenDutyMenu()
    eq(nuiCount('open'), 1)
    eq(lastNui('open').state.onDuty, false)
end)

test('duty menu: close NUI callback releases focus and clears roster pushes', function()
    setup()
    OpenDutyMenu()
    eq(stub.invokeNui('close'), 'ok')
    eq(stub.nuiFocus.focused, false)

    -- with the menu closed, roster broadcasts must no longer reach the NUI
    local before = nuiCount('roster') -- includes the push from the open above
    setStatus(1, 'busy', 'M-24')
    eq(nuiCount('roster'), before)
end)

test('duty menu: open pushes state and fetches the roster via callback', function()
    setup()
    LocalPlayer.state.emsStatus = 'available'   -- as persisted from an earlier session
    LocalPlayer.state.emsCallsign = 'M-9'
    setStatus(1, 'available', 'M-9')

    OpenDutyMenu()
    local msg = lastNui('open')
    eq(msg.state.status, 'available')
    eq(msg.state.callsign, 'M-9')
    eq(msg.state.onDuty, true)

    local roster = lastNui('roster')
    isTrue(roster ~= nil, 'roster forwarded to the NUI on open')
    local me = roster.roster[1]
    eq(me.callsign, 'M-9')
    eq(me.self, true) -- source came from stub.localSource
    eq(me.onDuty, true)
end)

test('duty menu: live roster broadcast updates the open menu', function()
    setup()
    OpenDutyMenu()
    local before = nuiCount('roster')
    setStatus(1, 'busy', 'M-24')
    eq(nuiCount('roster'), before + 1)
    eq(lastNui('roster').roster[1].callsign, 'M-24')

    -- and while closed, nothing is pushed
    stub.invokeNui('close')
    setStatus(1, 'available', 'M-24')
    eq(nuiCount('roster'), before + 1)
end)

test('duty menu: reopen restores status and callsign from the statebag', function()
    setup()
    OpenDutyMenu()
    stub.invokeNui('save', { status = 'outofservice', callsign = 'm-24' })

    -- server-side persistence path: the save must replicate to the statebag
    eq(stub.statebagLog[#stub.statebagLog].key, 'emsCallsign')
    eq(stub.statebagLog[#stub.statebagLog].value, 'M-24')

    stub.invokeNui('close')
    OpenDutyMenu()
    eq(lastNui('open').state.status, 'outofservice')
    eq(lastNui('open').state.callsign, 'M-24')
end)

test('duty menu: save rejects an unknown status preset', function()
    setup()
    OpenDutyMenu()
    stub.invokeNui('save', { status = 'raid-boss', callsign = 'M-24' })

    eq(#stub.serverEvents, 0)
    eq(#stub.statebagLog, 0)
    local note = stub.notifyLog[#stub.notifyLog]
    isTrue(note ~= nil and note.msg:find('Invalid duty status', 1, true) ~= nil, 'invalid-status notify')
end)

test('duty menu: save rejects callsigns with illegal characters', function()
    setup()
    OpenDutyMenu()
    stub.invokeNui('save', { status = 'busy', callsign = 'M-24<script>' })

    eq(#stub.serverEvents, 0)
    eq(#stub.statebagLog, 0)
end)

test('duty menu: save uppercases, truncates, replicates and syncs the server', function()
    setup()
    OpenDutyMenu()
    eq(stub.invokeNui('save', { status = 'busy', callsign = 'm-24' }), 'ok')

    local setEvents = 0
    for _, e in ipairs(stub.serverEvents) do
        if e.name == 'qb-emsjob:server:SetDutyStatus' then
            setEvents = setEvents + 1
            eq(e.args[1], 'busy')
            eq(e.args[2], 'M-24')
        end
    end
    eq(setEvents, 1)

    isTrue(#stub.statebagLog >= 2, 'emsStatus + emsCallsign replicated')
    eq(stub.statebagLog[#stub.statebagLog].key, 'emsCallsign')
    eq(stub.statebagLog[#stub.statebagLog].value, 'M-24')
    isTrue(stub.notifyLog[#stub.notifyLog].msg:find('Duty status saved', 1, true) ~= nil, 'saved notify')
end)

test('duty menu: QBCore:Client:SetDuty pushes fresh state to the open menu', function()
    setup()
    OpenDutyMenu()
    local before = nuiCount('state')
    stub.fireEvent('QBCore:Client:SetDuty', 1, false)

    eq(nuiCount('state'), before + 1)
    eq(lastNui('state').state.onDuty, false)
    eq(stub.players[1].PlayerData.job.onduty, true) -- other handler (main.lua) untouched
end)

test('duty menu: resource stop releases NUI focus', function()
    setup()
    OpenDutyMenu()
    stub.fireEvent('onResourceStop', 0, 'some-other-resource')
    eq(stub.nuiFocus.focused, true) -- unrelated resource: untouched

    stub.fireEvent('onResourceStop', 0, 'qb-emsjob')
    eq(stub.nuiFocus.focused, false)
end)

 ---------------------------------------------------------------------------
 -- Runner
 ---------------------------------------------------------------------------

print(('qb-emsjob test suite - %d tests'):format(#tests))
print(('running under %s'):format(_VERSION))
print(string.rep('-', 60))

for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        print(('PASS  %s'):format(t.name))
    else
        failed = failed + 1
        print(('FAIL  %s\n      %s'):format(t.name, tostring(err)))
    end
end

print(string.rep('-', 60))
print(('%d passed, %d failed'):format(#tests - failed, failed))

if failed > 0 then
    os.exit(1)
end
