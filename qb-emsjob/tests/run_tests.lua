--[[
    qb-emsjob | tests/run_tests.lua
    Loads the REAL config.lua, locale.lua and the server modules under the
    stub environment, then unit-tests the server-side validation logic:

      - grade/duty/job checks + revive/heal distance & item validation
      - billing (instant vs invoices) + insurance + respawn fees
      - EMS alert relay (server/ems_alerts.lua)
      - duty roster sync (server/duty_menu.lua)
      - useable item registration (server/items.lua), incl. ox_inventory fallback
      - target bridge (client/target_bridge.lua): qb-target vs ox_target (Qbox)
      - FRAMEWORKS.md detection-order table stays in sync with the real code
      - duty menu NUI controller (client/duty_menu.lua) via statebag + NUI stubs
      - garage controller (client/garage.lua) via qb-target + vehicle stubs
      - revive/laststand controller (client/revive.lua) with fake-time thread stepping

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
dofile('bridge.lua') -- shared optional-resource detection (Bridge globals)
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
-- only registered here, never fired, and no target backend is declared yet —
-- so keep Config.UseTarget = false to leave the 3D-text thread inert. The
-- target bridge declares qb-target as the default backend in setup().
-- Blips stay disabled: their CreateThread would start a refresh loop that
-- the stubs cannot step deterministically.
Config.UseTarget = false
Config.EnableBlips = false
dofile('client/main.lua')
dofile('client/target_bridge.lua')
dofile('client/duty_menu.lua')
dofile('client/garage.lua')
dofile('client/revive.lua')

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

    -- QBCore stack defaults for the runtime bridges; Qbox tests override
    -- them. The target bridge caches its backend in a module-local that
    -- survives reset, so re-arm detection every test.
    stub.started['qb-target'] = true
    stub.started['qb-phone'] = true -- classic qb-phone implements sendInvoice
    TargetBridgeReset()
    Bridge.ResetCaches()

    -- Client scenario globals (client/main.lua): on-duty, logged-in medic.
    -- duty_menu.lua also keeps module-local menu state across tests, so
    -- force the menu closed for a clean start (no-op when already closed).
    OnDuty = true
    isLoggedIn = true
    PlayerJob = { name = 'ambulance', label = 'EMS', onduty = true, grade = { level = 3 } }
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

test('duty toggle flips onduty for EMS and rebroadcasts the roster', function()
    setup()
    stub.players[1].PlayerData.job.onduty = false
    stub.fireEvent('qb-emsjob:server:ToggleDuty', 1)
    eq(stub.players[1].PlayerData.job.onduty, true)

    -- the roster must refresh so the duty menu shows the new duty state
    eq(eventsTo('qb-emsjob:client:RosterUpdated', 1), 1)
    eq(lastRosterFor(1)[1].onDuty, true)
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

    -- medic has bandages -> event fires; the delivered UseBandage handler
    -- runs in its own thread and blocks on a progress bar, so drive it to
    -- completion here (fake time) instead of leaving it parked for later
    -- tests to accidentally resume
    stub.advanceTime(0)
    fn(1)
    eq(eventsTo('qb-emsjob:client:UseBandage', 1), 1)
    stub.advanceTime(6000)
    -- direct resumeThreads calls: stepThreads is declared later in this file
    stub.resumeThreads()
    stub.resumeThreads()

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
    PlayerJob.name = 'mechanic' -- IsEMS() reads the client-side PlayerJob global
    OpenDutyMenu()
    eq(nuiCount('open'), 0)
    eq(stub.nuiFocus.focused, false)

    PlayerJob.name = 'ambulance'
    OpenDutyMenu()
    eq(nuiCount('open'), 1)
    eq(stub.nuiFocus.focused, true)
end)

test('duty menu: off-duty EMS still opens the menu', function()
    setup()
    stub.players[1].PlayerData.job.onduty = false
    OnDuty = false -- mirror the client-side duty flag
    local before = nuiCount('open')
    OpenDutyMenu()
    eq(nuiCount('open'), before + 1)
    eq(lastNui('open').state.onDuty, false)
end)

-- KVP restore must be tested BEFORE any test saves menu state: once the
-- save path runs, the controller's session memory is non-nil and the KVP
-- read branch is skipped for the rest of the process.
test('duty menu: KVP persistence restores state after a full client restart', function()
    setup()
    -- Simulate the previous session having saved a status + call-sign:
    -- after a full restart the statebag is empty but the KVPs remain.
    stub.kvp['ems_status'] = 'busy'
    stub.kvp['ems_callsign'] = 'M-99'

    OpenDutyMenu()
    local msg = lastNui('open')
    eq(msg.state.status, 'busy')
    eq(msg.state.callsign, 'M-99')

    -- a fresh save re-persists through the same path (status as-is,
    -- call-sign uppercased)
    stub.invokeNui('save', { status = 'outofservice', callsign = 'm-1' })
    eq(stub.kvp['ems_status'], 'outofservice')
    eq(stub.kvp['ems_callsign'], 'M-1')

    -- and clearing the status also clears the KVP (nil round-trip)
    stub.invokeNui('save', { status = nil, callsign = '' })
    eq(stub.kvp['ems_status'], nil)
    eq(stub.kvp['ems_callsign'], '')
end)

test('duty menu: statebag wins over KVP after a resource restart', function()
    setup()
    stub.kvp['ems_status'] = 'busy'
    stub.kvp['ems_callsign'] = 'M-99'
    LocalPlayer.state.emsStatus = 'outofservice'   -- newer resource-restart state
    LocalPlayer.state.emsCallsign = 'M-11'

    OpenDutyMenu()
    local msg = lastNui('open')
    eq(msg.state.status, 'outofservice')
    eq(msg.state.callsign, 'M-11')
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

test('duty menu: open embeds the cached roster and refreshes via callback', function()
    setup()
    LocalPlayer.state.emsStatus = 'available'   -- as persisted from an earlier session
    LocalPlayer.state.emsCallsign = 'M-9'
    setStatus(1, 'available', 'M-9')            -- broadcast arrives while closed

    OpenDutyMenu()
    local msg = lastNui('open')
    eq(msg.state.status, 'available')
    eq(msg.state.callsign, 'M-9')
    eq(msg.state.onDuty, true)

    -- the open message already carries the roster: no "No colleagues" flash
    isTrue(msg.roster ~= nil, 'open message embeds the cached roster')
    local me = msg.roster[1]
    eq(me.callsign, 'M-9')
    eq(me.self, true) -- source came from stub.localSource
    eq(me.onDuty, true)

    -- the authoritative refresh still lands right after open
    local roster = lastNui('roster')
    isTrue(roster ~= nil, 'roster forwarded to the NUI on open')
    eq(roster.roster[1].callsign, 'M-9')
end)

test('duty menu: live roster broadcast updates the open menu', function()
    setup()
    OpenDutyMenu()
    local before = nuiCount('roster')
    setStatus(1, 'busy', 'M-24')
    eq(nuiCount('roster'), before + 1)
    eq(lastNui('roster').roster[1].callsign, 'M-24')

    -- and while closed, nothing is pushed (the cache still updates)
    stub.invokeNui('close')
    setStatus(1, 'available', 'M-24')
    eq(nuiCount('roster'), before + 1)

    -- reopening embeds the latest roster without waiting for the refresh
    OpenDutyMenu()
    eq(lastNui('open').roster[1].callsign, 'M-24')
    eq(lastNui('open').roster[1].status, 'available')
    eq(nuiCount('roster'), before + 2)
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
 -- Garage controller (client/garage.lua)
 ---------------------------------------------------------------------------

--- Register the garage/duty zones as qb-target would on resource start.
--- (qb-target declared started so the bridge routes there; the Qbox tests
--- below override it with ox_target.)
local function startGarage()
    stub.started['qb-target'] = true
    Config.UseTarget = true
    stub.fireEvent('onResourceStart', 0, 'qb-emsjob')
end

--- Return the zone option action with the given label (nil if absent).
local function zoneAction(name, label)
    local zone = stub.zones[name]
    if not zone then return nil end
    for _, opt in ipairs(zone.options) do
        if opt.label == label then return opt.action end
    end
    return nil
end

test('garage: hospital zones register with take-out and store actions', function()
    setup()
    startGarage()

    isTrue(stub.zones['ems_garage_central'] ~= nil)
    isTrue(stub.zones['ems_heli_central'] ~= nil)
    isTrue(stub.zones['ems_garage_sandy'] ~= nil)
    isTrue(stub.zones['ems_heli_paleto'] == nil) -- helipad disabled in config

    isTrue(zoneAction('ems_garage_central', _L('target_garage')) ~= nil, 'take-out action')
    isTrue(zoneAction('ems_garage_central', _L('target_store')) ~= nil, 'store action')
end)

test('garage: taking out an ambulance spawns, preps, keys and warps', function()
    setup()
    startGarage()

    zoneAction('ems_garage_central', _L('target_garage'))()

    eq(#stub.spawnLog, 1)
    eq(stub.spawnLog[1].model, 'ambulance')
    local veh = stub.spawnLog[1].veh
    local v = stub.vehicles[veh]
    eq(v.heading, 82.0)                       -- central garage spawn heading
    isTrue(v.plate:find('EMS', 1, true) ~= nil, 'plate starts with EMS')
    eq(v.engineOn, true)
    eq(v.fuel, 100.0)
    eq(v.livery, 1)                           -- ground vehicles get a livery
    eq(stub.warped.veh, veh)
    eq(stub.warped.seat, -1)
    eq(eventCount('vehiclekeys:client:SetOwner'), 1)
end)

test('garage: spawn is refused with a notify when the spot is blocked', function()
    setup()
    startGarage()

    local realCb = stub.callbacks['qb-emsjob:server:CanSpawnVehicle']
    stub.callbacks['qb-emsjob:server:CanSpawnVehicle'] = function(_, cb) cb(false) end
    zoneAction('ems_garage_central', _L('target_garage'))()
    stub.callbacks['qb-emsjob:server:CanSpawnVehicle'] = realCb

    eq(#stub.spawnLog, 0)
    local note = stub.notifyLog[#stub.notifyLog]
    isTrue(note ~= nil and note.msg:find('spawn point is blocked', 1, true) ~= nil, 'blocked notify')
end)

test('garage: helipad take out spawns a helicopter without a livery', function()
    setup()
    startGarage()

    zoneAction('ems_heli_central', _L('target_heli'))()

    eq(#stub.spawnLog, 1)
    eq(stub.spawnLog[1].model, 'policemav')   -- first configured heli, qb-input absent
    local v = stub.vehicles[stub.spawnLog[1].veh]
    eq(v.livery, nil)                         -- helis get no livery
    eq(stub.warped.veh, stub.spawnLog[1].veh)
end)

test('garage: storing an ambulance deletes it', function()
    setup()
    startGarage()
    stub.vehicles[777] = { model = joaat('ambulance'), class = 0, plate = 'EMS999' }
    stub.pedInVehicle = 777

    zoneAction('ems_garage_central', _L('target_store'))()

    eq(#stub.deletedVehicles, 1)
    eq(stub.deletedVehicles[1], 777)
    eq(stub.vehicles[777], nil)
    isTrue(stub.notifyLog[#stub.notifyLog].msg:find('stored', 1, true) ~= nil, 'stored notify')
end)

test('garage: storing a civilian vehicle is refused', function()
    setup()
    startGarage()
    stub.vehicles[888] = { model = joaat('sultan'), class = 0, plate = 'CIV001' }
    stub.pedInVehicle = 888

    zoneAction('ems_garage_central', _L('target_store'))()

    eq(#stub.deletedVehicles, 0)
    isTrue(stub.notifyLog[#stub.notifyLog].msg:find('must be in an ambulance', 1, true) ~= nil, 'not-in-ambulance notify')
end)

test('garage: storing while on foot is refused', function()
    setup()
    startGarage()
    stub.pedInVehicle = 0

    zoneAction('ems_garage_central', _L('target_store'))()

    eq(#stub.deletedVehicles, 0)
    isTrue(stub.notifyLog[#stub.notifyLog].msg:find('must be in an ambulance', 1, true) ~= nil, 'not-in-ambulance notify')
end)

test('garage: a police mav counts as an emergency helicopter', function()
    setup()
    startGarage()
    stub.vehicles[999] = { model = joaat('policemav'), class = 15, plate = 'HELI01' }
    stub.pedInVehicle = 999

    zoneAction('ems_heli_central', _L('target_store'))()

    eq(#stub.deletedVehicles, 1)
    eq(stub.deletedVehicles[1], 999)
end)

test('garage: resource stop removes the registered zones', function()
    setup()
    startGarage()
    stub.fireEvent('onResourceStop', 0, 'qb-emsjob')

    eq(stub.zones['ems_garage_central'], nil)
    eq(stub.zones['ems_heli_central'], nil)
    isTrue(#stub.removedZones >= 5, 'duty + garage + helipad zones removed')
end)

 ---------------------------------------------------------------------------
 -- Target bridge: qb-target vs ox_target (Qbox) selection
 ---------------------------------------------------------------------------

test('target bridge: routes zones to qb-target when it is started', function()
    setup()
    stub.started['qb-target'] = true

    TargetAddBoxZone('bridge_qb', V(1, 2, 3), 4.0, 5.0, { heading = 90.0 },
        { options = { { label = 'L', icon = 'i', job = 'ambulance', action = function() end } }, distance = 2.5 })

    isTrue(stub.zones['bridge_qb'] ~= nil, 'zone went to qb-target')
    eq(stub.zones['bridge_qb'].length, 4.0)
    isTrue(next(stub.oxZones) == nil, 'nothing went to ox_target')

    TargetRemoveZone('bridge_qb')
    eq(#stub.removedZones, 1)
end)

test('target bridge: maps zones to ox_target shape for Qbox', function()
    setup()
    stub.started['qb-target'] = nil -- Qbox: no qb-target resource
    stub.started['ox_target'] = true

    local action = function() end
    TargetAddBoxZone('bridge_ox', V(1, 2, 3), 4.0, 5.0, { heading = 90.0, debugPoly = true },
        { options = { { label = 'Loot', icon = 'fa-box', job = 'ambulance', action = action } }, distance = 2.5 })

    eq(next(stub.oxZones) ~= nil, true, 'zone went to ox_target')
    local id, cfg = next(stub.oxZones)
    eq(cfg.coords.x, 1.0)
    eq(cfg.size.x, 4.0)
    eq(cfg.size.y, 5.0)
    eq(cfg.rotation, 90.0)
    eq(cfg.debug, true)
    eq(#cfg.options, 1)
    eq(cfg.options[1].label, 'Loot')
    eq(cfg.options[1].groups, 'ambulance')   -- qb-target `job` -> ox `groups`
    eq(cfg.options[1].onSelect, action)      -- qb-target `action` -> ox `onSelect`
    eq(cfg.options[1].distance, 2.5)
    isTrue(stub.zones['bridge_ox'] == nil, 'nothing went to qb-target')

    -- removal maps by name to the ox zone id
    TargetRemoveZone('bridge_ox')
    eq(#stub.oxRemovedZoneIds, 1)
    eq(stub.oxRemovedZoneIds[1], id)
end)

test('target bridge: entity options map to ox_target and remove by id', function()
    setup()
    stub.started['qb-target'] = nil -- Qbox: no qb-target resource
    stub.started['ox_target'] = true

    local ped = 71234
    TargetAddEntity(ped, {
        options = { { label = 'Revive', canInteract = function() return true end, action = function() end } },
        distance = 2.0,
    })

    local id, cfg = next(stub.oxEntityIds)
    isTrue(id ~= nil, 'entity target registered on ox_target')
    eq(cfg.entity, ped)
    eq(cfg.options[1].label, 'Revive')
    isTrue(cfg.options[1].canInteract ~= nil, 'canInteract passed through')
    eq(cfg.options[1].distance, 2.0)

    TargetRemoveEntity(ped)
    eq(#stub.oxRemovedEntityIds, 1)
    eq(stub.oxRemovedEntityIds[1], id)
end)

test('target bridge: qb-target still wins when both are started', function()
    setup()
    stub.started['qb-target'] = true
    stub.started['ox_target'] = true

    TargetAddBoxZone('bridge_both', V(0, 0, 0), 2.0, 2.0, {}, { options = {}, distance = 2.0 })

    isTrue(stub.zones['bridge_both'] ~= nil, 'qb-target preferred on hybrid stacks')
    isTrue(next(stub.oxZones) == nil, 'ox_target untouched')
end)

 ---------------------------------------------------------------------------
 -- Qbox bridges: society money + phone invoices
 ---------------------------------------------------------------------------

test('society credit: prefers qbx_management when it is started', function()
    setup()
    Config.BillingMode = 'instant'
    Config.Insurance.enabled = false
    stub.players[2].PlayerData.money.bank = 5000 -- fund the patient fully
    stub.started['qbx_management'] = true

    local billed = EMSBill(2, 2500, 'qbox society')
    eq(billed, 2500)
    eq(#stub.societyLog, 1)
    eq(stub.societyLog[1].via, 'qbx')
    eq(stub.societyLog[1].account, 'ambulance')
    eq(stub.societyLog[1].amount, 2500)
    eq(eventCount('qb-management:server:addSocietyMoney'), 0)
end)

test('society credit: falls back to Renewed-Banking, then the legacy event', function()
    setup()
    Config.BillingMode = 'instant'
    Config.Insurance.enabled = false

    -- Renewed-Banking path (no qbx_management)
    stub.started['Renewed-Banking'] = true
    EMSBill(2, 1000, 'renewed society')
    eq(#stub.societyLog, 1)
    eq(stub.societyLog[1].via, 'renewed')
    eq(eventCount('qb-management:server:addSocietyMoney'), 0)

    -- Legacy event path (neither export resource started)
    stub.started['Renewed-Banking'] = nil
    stub.players[2].PlayerData.money.bank = 1000
    EMSBill(2, 1000, 'legacy society')
    eq(#stub.societyLog, 1) -- unchanged: event path used
    eq(eventCount('qb-management:server:addSocietyMoney'), 1)
end)

test('invoices: qbx_phone gets a direct phone_invoices row, not the event', function()
    setup()
    Config.BillingMode = 'invoices'
    Config.Insurance.enabled = false
    stub.started['qb-phone'] = nil -- Qbox ships qbx_phone
    stub.started['qbx_phone'] = true

    local billed = EMSBill(2, 2500, 'qbox invoice')
    eq(billed, 2500)
    eq(eventCount('qb-phone:server:sendInvoice'), 0)

    isTrue(stub.insertLog ~= nil and #stub.insertLog == 1, 'invoice row inserted')
    local ins = stub.insertLog[1]
    isTrue(ins.query:find('phone_invoices', 1, true) ~= nil, 'writes phone_invoices')
    isTrue(ins.query:find('sendercitizenid', 1, true) ~= nil, 'schema matches stock phone_invoices')
    eq(ins.params[1], 'PAT001')
    eq(ins.params[2], 2500)
    eq(ins.params[3], 'ambulance')

    Config.Insurance.enabled = true
end)

test('invoices: classic qb-phone still gets the event with no duplicate row', function()
    setup()
    Config.BillingMode = 'invoices'
    Config.Insurance.enabled = false
    stub.started['qb-phone'] = true

    EMSBill(2, 2500, 'classic invoice')
    eq(eventCount('qb-phone:server:sendInvoice'), 1)
    eq(stub.insertLog, nil)

    Config.Insurance.enabled = true
end)

test('garage menu: qb-input opens when a spot lists multiple vehicles', function()
    setup()
    stub.started['qb-input'] = true

    local shown = nil
    stub.registerExport('qb-input', 'ShowInput', function(_, data)
        shown = data
        return { vehicle = 'ambulance2' }
    end)

    -- second vehicle makes the picker open (single-vehicle spots skip it)
    Config.Hospitals[1].garage.vehicles[2] = 'ambulance2'

    startGarage()
    local act = zoneAction('ems_garage_central', _L('target_garage'))
    isTrue(act ~= nil, 'garage action registered')
    act()

    isTrue(shown ~= nil, 'qb-input ShowInput called')
    eq(shown.header, Config.Hospitals[1].label)
    eq(shown.inputs[1].options[1].value, 'ambulance')
    eq(shown.inputs[1].options[2].value, 'ambulance2')

    -- picked model reaches the spawner
    eq(stub.spawnLog[#stub.spawnLog].model, 'ambulance2')

    -- cleanup so later tests see the one-vehicle config
    Config.Hospitals[1].garage.vehicles[2] = nil
end)

test('garage menu: ox_lib inputDialog is used when qb-input is absent (Qbox)', function()
    setup()
    stub.started['qb-input'] = nil
    stub.started['ox_lib'] = true

    local dialogArgs = nil
    lib = {
        inputDialog = function(header, rows)
            dialogArgs = { header = header, rows = rows }
            -- real ox_lib returns row values positionally
            return { 'ambulance2' }
        end,
    }

    Config.Hospitals[1].garage.vehicles[2] = 'ambulance2'

    startGarage()
    zoneAction('ems_garage_central', _L('target_garage'))()

    isTrue(dialogArgs ~= nil, 'lib.inputDialog called')
    eq(dialogArgs.rows[1].type, 'select')
    eq(dialogArgs.rows[1].options[1].value, 'ambulance')
    eq(dialogArgs.rows[1].options[2].value, 'ambulance2')
    eq(stub.spawnLog[#stub.spawnLog].model, 'ambulance2')

    lib = nil
    Config.Hospitals[1].garage.vehicles[2] = nil
end)

test('items: lookup falls back to ox_inventory when it is started', function()
    setup()
    stub.started['ox_inventory'] = true
    TargetBridgeReset()
    -- HealItem = 'bandage', ReviveItem = 'ifaks'. With ox_inventory active,
    -- the ox layer is authoritative: bandage exists ONLY there, ifaks ONLY in
    -- QBCore.Shared.Items (and must be ignored). Proves both preference and
    -- exclusion in one pass.
    stub.oxItems['bandage'] = { name = 'bandage', label = 'Bandage' }
    stub.QBCore.Shared.Items['bandage'] = nil
    stub.QBCore.Shared.Items['ifaks'] = { name = 'ifaks', label = 'Ifaks' }
    -- useableItems survives reset (load-time registrations), so clear both
    -- to prove the re-registration itself chooses the right inventory layer
    stub.useableItems['bandage'] = nil
    stub.useableItems['ifaks'] = nil

    -- re-run the useable-item registration exactly as a resource restart would
    dofile('server/items.lua')

    isTrue(stub.useableItems['bandage'] ~= nil, 'ox_inventory item registered useable')
    isTrue(stub.useableItems['ifaks'] == nil, 'QBCore-only item ignored while ox_inventory is active')
end)

 ---------------------------------------------------------------------------
 -- Revive / laststand controller (client/revive.lua)
 ---------------------------------------------------------------------------

local function serverEventCount(name)
    local n = 0
    for _, e in ipairs(stub.serverEvents) do
        if e.name == name then n = n + 1 end
    end
    return n
end

--- Resume parked threads. passes=1 is the steady-state tick (one loop
--- iteration per fake second); the initial step after firing an event uses
--- extra passes so nested CreateThread bodies (e.g. the countdown thread
--- spawned by enterLaststand inside the death-watch pass) get their first run.
local function stepThreads(passes)
    for _ = 1, passes or 1 do
        stub.resumeThreads()
    end
end

test('revive: entering laststand replicates the countdown and alerts EMS', function()
    setup()
    stub.peds[1].dead = true

    stepThreads(3)

    local ls = LocalPlayer.state.laststand
    isTrue(type(ls) == 'number' and ls > 0 and ls <= 300, 'laststand countdown replicated')
    eq(serverEventCount('qb-emsjob:server:PlayerDowned'), 1)
    local blips = 0
    for _ in pairs(stub.blips) do blips = blips + 1 end
    eq(blips, 1) -- flashing downed blip on own position
end)

test('revive: the bleed-out countdown drains with fake time and kills at zero', function()
    setup()
    stub.peds[1].dead = true
    stepThreads(3)

    -- one fake second per pass; tick until the countdown reads 1 regardless
    -- of how many iterations the initial step burned
    local guard = 0
    while type(LocalPlayer.state.laststand) == 'number' and LocalPlayer.state.laststand > 1 do
        stub.advanceTime(1000)
        stepThreads()
        guard = guard + 1
        isTrue(guard < 600, 'countdown reached 1')
    end

    stub.advanceTime(1000)
    stepThreads()

    -- bled out: downed state cleared, fully dead
    eq(LocalPlayer.state.laststand, false)
    eq(LocalPlayer.state.isdead, true)
end)

test('revive: being revived clears downed state and restores the ped', function()
    setup()
    stub.peds[1].dead = true
    stepThreads(3)
    LocalPlayer.state.isdead = true

    stub.fireEvent('qb-emsjob:client:Revived', 1, 2500)

    eq(LocalPlayer.state.laststand, false)
    eq(LocalPlayer.state.isdead, false)
    eq(stub.peds[1].dead, false)   -- went through NetworkResurrectLocalPlayer
    eq(stub.peds[1].health, 200)
    isTrue(stub.notifyLog[#stub.notifyLog].msg:find('You were revived by EMS', 1, true) ~= nil, 'revived notify')
end)

test('revive: holding E respawns at the nearest hospital and bills', function()
    setup()
    stub.peds[1].dead = true
    stepThreads(3)
    LocalPlayer.state.isdead = true
    LocalPlayer.state.laststand = false
    stub.advanceTime(0) -- pin the hold timer to fake time before it starts

    stub.holdE = true
    -- hold accumulates across ticks; the strict >3000ms threshold trips on
    -- tick 5 (captured at t=1000, exceeded at t=5000), and respawn's two
    -- internal Wait(500) calls need two more ticks
    for _ = 1, 8 do
        stub.advanceTime(1000)
        stepThreads()
    end

    eq(stub.peds[1].coords.x, 295.83) -- central hospital respawn point
    eq(stub.peds[1].coords.y, -1446.96)
    eq(stub.peds[1].dead, false)
    eq(stub.peds[1].health, 150)      -- respawn restores at reduced health
    eq(serverEventCount('qb-emsjob:server:RespawnBilled'), 1)
end)

test('revive: releasing E cancels the respawn hold', function()
    setup()
    stub.peds[1].dead = true
    stepThreads(3)
    LocalPlayer.state.isdead = true
    LocalPlayer.state.laststand = false
    stub.advanceTime(0) -- pin the hold timer to fake time before it starts

    stub.holdE = true
    stub.advanceTime(2000)
    stepThreads()
    stub.holdE = false
    stub.advanceTime(5000)
    stepThreads()

    eq(serverEventCount('qb-emsjob:server:RespawnBilled'), 0)
    eq(stub.peds[1].coords.x, 0) -- never teleported
end)

test('revive: on-duty EMS gets target options on a nearby downed player', function()
    setup()
    stub.remoteStates[2] = { laststand = 120 }
    stub.setPed(2, V(3, 0, 0), 0)

    stepThreads()

    local tgt = stub.entityTargets[2]
    isTrue(tgt ~= nil, 'target options attached to the downed ped')
    isTrue(#tgt.options >= 2, 'revive + heal options present')
    eq(tgt.distance, Config.ReviveDistance)

    -- once the player is no longer nearby, the options are removed again
    stub.setPed(2, V(500, 0, 0), 0)
    stepThreads()
    eq(stub.entityTargets[2], nil)
    isTrue(#stub.removedEntityTargets >= 1, 'stale target removed')
end)

test('revive: starting a revive runs the progress bar and signals the server', function()
    setup()
    stub.remoteStates[2] = { laststand = 120 }
    stub.setPed(2, V(3, 0, 0), 0)

    -- force a detach/reattach pass so these options come from THIS test's
    -- tracker run (revive.lua's module-local trackedPeds survives resets)
    stub.setPed(2, V(500, 0, 0), 0)
    stepThreads()
    stub.setPed(2, V(3, 0, 0), 0)
    stepThreads()

    local action
    for _, opt in ipairs(stub.entityTargets[2].options) do
        if opt.label == _L('target_revive') then action = opt.action end
    end
    isTrue(action ~= nil)

    stub.advanceTime(0) -- enable fake time so the progress bar completes
    stub.runInThread(action)
    stub.advanceTime(6000)
    stepThreads(2) -- pass 1 finishes the progress bar, pass 2 releases the waiter

    eq(serverEventCount('qb-emsjob:server:RevivePlayer'), 1)
    eq(stub.serverEvents[#stub.serverEvents].args[1], 2)
end)

test('revive: healing a downed player redirects to the revive flow', function()
    setup()
    stub.remoteStates[2] = { laststand = 90 }
    stub.setPed(2, V(3, 0, 0), 0)

    -- force a detach/reattach pass (see the revive-flow test above)
    stub.setPed(2, V(500, 0, 0), 0)
    stepThreads()
    stub.setPed(2, V(3, 0, 0), 0)
    stepThreads()

    local action
    for _, opt in ipairs(stub.entityTargets[2].options) do
        if opt.label == _L('target_heal') then action = opt.action end
    end

    stub.advanceTime(0)
    stub.runInThread(action)
    stub.advanceTime(6000)
    stepThreads(2) -- pass 1 finishes the progress bar, pass 2 releases the waiter

    eq(serverEventCount('qb-emsjob:server:RevivePlayer'), 1)
    eq(serverEventCount('qb-emsjob:server:HealPlayer'), 0)
end)

test('revive: bandage heals, starts a cooldown and is refused while downed', function()
    setup()
    LocalPlayer.state.laststand = 120
    stub.runInThread(function() stub.fireEvent('qb-emsjob:client:UseBandage', 1) end)
    isTrue(stub.notifyLog[#stub.notifyLog].msg:find('cannot use this right now', 1, true) ~= nil, 'refused while downed')

    setup() -- clears the downed state
    -- jump far past any selfHealReady cooldown left over by earlier tests
    -- (selfHealReady is a module-local in revive.lua that survives resets)
    stub.advanceTime(600000)
    stub.runInThread(function() stub.fireEvent('qb-emsjob:client:UseBandage', 1) end)
    stub.advanceTime(6000)
    stepThreads(2) -- pass 1 finishes the progress bar, pass 2 releases the waiter

    eq(stub.peds[1].health, 200) -- clamped to max health
    isTrue(stub.notifyLog[#stub.notifyLog].msg:find('You feel a little better', 1, true) ~= nil, 'self-heal notify')

    -- second use inside the cooldown window is rejected
    stub.runInThread(function() stub.fireEvent('qb-emsjob:client:UseBandage', 1) end)
    isTrue(stub.notifyLog[#stub.notifyLog].msg:find('recently treated', 1, true) ~= nil, 'cooldown notify')
end)

 ---------------------------------------------------------------------------
 -- Documentation accuracy: FRAMEWORKS.md detection order vs the real code
 ---------------------------------------------------------------------------

--- The framework reference doc (FRAMEWORKS.md) claims specific detection
--- orders for every optional resource. These tests parse the doc's
--- detection-order table and assert each priority chain against the
--- resource source, so the two can never drift apart silently: editing one
--- without the other fails CI. Doc rows are parsed (not hard-coded) and
--- source checks are plain substring finds, so pure prose edits stay free.

local frameworksDoc
local sourceOf = {}
do
    local f = io.open('FRAMEWORKS.md', 'r')
    isTrue(f ~= nil, 'FRAMEWORKS.md is readable (run lua from the qb-emsjob directory)')
    frameworksDoc = f:read('*a')
    f:close()

    for key, path in pairs({
        bridge = 'bridge.lua',
        targets = 'client/target_bridge.lua',
        items = 'server/items.lua',
        billing = 'server/billing.lua',
        garage = 'client/garage.lua',
        manifest = 'fxmanifest.lua',
    }) do
        local sf = io.open(path, 'r')
        isTrue(sf ~= nil, path .. ' is readable')
        sourceOf[key] = sf:read('*a')
        sf:close()
    end
end

--- One trimmed cell list from a markdown table row (name + data columns).
local function splitRow(line)
    local cells = {}
    for cell in line:gmatch('[^|]+') do
        cells[#cells + 1] = cell:match('^%s*(.-)%s*$')
    end
    return cells
end

--- Parse one row of the "## Detection order" table by integration point.
local function detectionRow(integrationPoint)
    local row = nil
    for line in frameworksDoc:gmatch('[^\r\n]+') do
        if line:sub(1, 1) == '|' then
            local cells = splitRow(line)
            if cells[1] == integrationPoint and #cells >= 5 then
                row = {
                    priority = cells[2],
                    qbcore = cells[3],
                    qbox = cells[4],
                    neither = cells[5],
                }
            end
        end
    end
    return row
end

--- Plain (non-pattern) substring find against a loaded source file.
local function sourceHas(key, snippet)
    return sourceOf[key]:find(snippet, 1, true) ~= nil
end

test('FRAMEWORKS: detection-order table lists all six integration points', function()
    for _, name in ipairs({
        'Core object', 'Interaction targets', 'Item existence', 'Invoices',
        'Society credit (instant billing)', 'Garage vehicle picker',
    }) do
        isTrue(detectionRow(name) ~= nil, 'row present: ' .. name)
    end
end)

test('FRAMEWORKS: targets row matches target_bridge (qb-target before ox_target)', function()
    local row = detectionRow('Interaction targets')
    isTrue(row.priority:find('qb-target', 1, true) ~= nil, 'doc names qb-target')
    isTrue(row.priority:find('ox_target', 1, true) ~= nil, 'doc names ox_target')
    isTrue(row.priority:find('qb-target', 1, true) < row.priority:find('ox_target', 1, true), 'doc order: qb-target first')
    isTrue(sourceHas('targets', "Bridge.IsStarted('qb-target')"), 'code checks qb-target')
    isTrue(sourceHas('targets', "Bridge.IsStarted('ox_target')"), 'code checks ox_target')
    isTrue(sourceOf.targets:find("Bridge.IsStarted('qb-target')", 1, true) <
        sourceOf.targets:find("Bridge.IsStarted('ox_target')", 1, true), 'code order: qb-target first')
    isTrue(sourceHas('targets', 'interaction points are disabled'), 'warns once when neither is started')
end)

test('FRAMEWORKS: item row matches items.lua (ox_inventory preferred over Shared.Items)', function()
    local row = detectionRow('Item existence')
    isTrue(row.priority:find('ox_inventory', 1, true) ~= nil, 'doc names ox_inventory')
    isTrue(row.priority:find('Shared.Items', 1, true) ~= nil, 'doc names Shared.Items')
    isTrue(row.priority:find('ox_inventory', 1, true) < row.priority:find('Shared.Items', 1, true), 'doc order: ox_inventory first')
    isTrue(sourceHas('items', "Bridge.IsStarted('ox_inventory')"), 'code checks ox_inventory')
    isTrue(sourceHas('items', 'QBCore.Shared.Items and QBCore.Shared.Items[item] ~= nil'), 'fallback guards Shared.Items')
end)

test('FRAMEWORKS: invoice row matches billing.lua (qb-phone event, then direct row)', function()
    local row = detectionRow('Invoices')
    isTrue(row.priority:find('qb-phone event', 1, true) ~= nil, 'doc: qb-phone event first')
    isTrue(row.priority:find('direct DB row', 1, true) ~= nil, 'doc: direct DB row second')
    isTrue(row.qbcore:find('qb-phone:server:sendInvoice', 1, true) ~= nil, 'doc names the event')
    isTrue(row.qbox:find('phone_invoices', 1, true) ~= nil, 'doc names the direct table')
    isTrue(sourceHas('billing', "Bridge.IsStarted('qb-phone')"), 'code checks qb-phone first')
    isTrue(sourceHas('billing', "TriggerEvent('qb-phone:server:sendInvoice'"), 'code fires the event')
    isTrue(sourceHas('billing', 'INSERT INTO phone_invoices'), 'code inserts the row as fallback')
    isTrue(sourceHas('billing', 'sendercitizenid'), 'row columns match the qbx_phone schema')
end)

test('FRAMEWORKS: society row matches billing.lua (qbx -> Renewed -> legacy event)', function()
    local row = detectionRow('Society credit (instant billing)')
    isTrue(row.priority:find('qbx_management', 1, true) ~= nil, 'doc names qbx_management')
    isTrue(row.priority:find('Renewed-Banking', 1, true) ~= nil, 'doc names Renewed-Banking')
    isTrue(row.priority:find('legacy event', 1, true) ~= nil, 'doc names the legacy event')
    isTrue(row.priority:find('qbx_management', 1, true) < row.priority:find('Renewed-Banking', 1, true), 'doc order: qbx first')
    isTrue(row.priority:find('Renewed-Banking', 1, true) < row.priority:find('legacy event', 1, true), 'doc order: Renewed second')
    isTrue(sourceHas('billing', "Bridge.IsStarted('qbx_management')"), 'code checks qbx_management')
    isTrue(sourceHas('billing', "Bridge.IsStarted('Renewed-Banking')"), 'code checks Renewed-Banking')
    isTrue(sourceHas('billing', "TriggerEvent('qb-management:server:addSocietyMoney'"), 'code ends at the legacy event')
    isTrue(sourceOf.billing:find("Bridge.IsStarted('qbx_management')", 1, true) <
        sourceOf.billing:find("Bridge.IsStarted('Renewed-Banking')", 1, true), 'code order: qbx first')
    isTrue(sourceOf.billing:find("Bridge.IsStarted('Renewed-Banking')", 1, true) <
        sourceOf.billing:find("TriggerEvent('qb-management:server:addSocietyMoney'", 1, true), 'code order: Renewed before legacy')
end)

test('FRAMEWORKS: picker row matches garage.lua (qb-input, ox_lib, first vehicle)', function()
    local row = detectionRow('Garage vehicle picker')
    isTrue(row.priority:find('qb-input', 1, true) ~= nil, 'doc names qb-input')
    isTrue(row.priority:find('ox_lib dialog', 1, true) ~= nil, 'doc names the ox_lib dialog')
    isTrue(row.priority:find('first vehicle', 1, true) ~= nil, 'doc names the first-vehicle fallback')
    isTrue(row.priority:find('qb-input', 1, true) < row.priority:find('ox_lib dialog', 1, true), 'doc order: qb-input first')
    isTrue(sourceHas('garage', "Bridge.IsStarted('qb-input')"), 'code checks qb-input')
    isTrue(sourceHas('garage', 'Bridge.GetOxLib()'), 'code resolves ox_lib through the shared bridge')
    isTrue(sourceHas('garage', 'model = cfg.vehicles[1]'), 'first vehicle is the code fallback')
    isTrue(sourceHas('garage', 'res[1] or res.vehicle'), 'ox_lib result read positionally with a fork fallback')
end)

test('FRAMEWORKS: core row matches the manifest hard dependencies', function()
    local row = detectionRow('Core object')
    isTrue(row.qbcore:find('qb-core', 1, true) ~= nil, 'doc: qb-core on classic QBCore')
    isTrue(row.qbox:find('GetCoreObject', 1, true) ~= nil, 'doc: QB bridge answers GetCoreObject')
    isTrue(sourceHas('manifest', "'qb-core',"), 'qb-core is a hard dependency')
    isTrue(sourceHas('manifest', "'oxmysql',"), 'oxmysql is a hard dependency')
    isTrue(sourceHas('manifest', "'bridge.lua',"), 'bridge.lua ships as a shared script')
    isTrue(not sourceHas('manifest', "'qb-target',"), 'qb-target is optional, not a dependency')
    isTrue(not sourceHas('manifest', "'PolyZone'"), 'PolyZone is optional, not a dependency')
end)

test('FRAMEWORKS: neither-resource columns match the actual fallbacks', function()
    isTrue(detectionRow('Interaction targets').neither:find('warn once', 1, true) ~= nil, 'doc: targets warn once')
    isTrue(detectionRow('Item existence').neither:find('falls back to shared items', 1, true) ~= nil, 'doc: items fall back')
    isTrue(detectionRow('Invoices').neither:find('direct DB row', 1, true) ~= nil, 'doc: invoices still land')
    isTrue(detectionRow('Society credit (instant billing)').neither:find('credit skipped', 1, true) ~= nil, 'doc: credit skipped')
    isTrue(detectionRow('Garage vehicle picker').neither:find('first configured vehicle', 1, true) ~= nil, 'doc: first vehicle')
end)

test('FRAMEWORKS: bridging-lives table matches the bridge.lua surface', function()
    isTrue(frameworksDoc:find('Bridge.IsStarted', 1, true) ~= nil, 'doc references Bridge.IsStarted')
    isTrue(frameworksDoc:find('Bridge.GetOxLib', 1, true) ~= nil, 'doc references Bridge.GetOxLib')
    isTrue(frameworksDoc:find('Bridge.ResetCaches', 1, true) ~= nil, 'doc references Bridge.ResetCaches')
    isTrue(sourceHas('bridge', 'function Bridge.IsStarted'), 'code defines Bridge.IsStarted')
    isTrue(sourceHas('bridge', 'function Bridge.GetOxLib'), 'code defines Bridge.GetOxLib')
    isTrue(sourceHas('bridge', 'function Bridge.ResetCaches'), 'code defines Bridge.ResetCaches')
    isTrue(frameworksDoc:find("require('@ox_lib/init.lua')", 1, true) ~= nil, 'doc documents the require fallback')
    isTrue(sourceHas('bridge', "pcall(require, '@ox_lib/init.lua')"), 'code implements it')
end)

 ---------------------------------------------------------------------------
 -- Runner
 ---------------------------------------------------------------------------

print(('qb-emsjob test suite - %d tests'):format(#tests))
print(('running under %s'):format(_VERSION))
print(string.rep('-', 60))

for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    t.ok, t.err = ok, tostring(err)
    if ok then
        print(('PASS  %s'):format(t.name))
    else
        failed = failed + 1
        print(('FAIL  %s\n      %s'):format(t.name, t.err))
    end
end

print(string.rep('-', 60))
print(('%d passed, %d failed'):format(#tests - failed, failed))

-- Render a results table on the GitHub Actions run summary page. In CI the
-- GITHUB_STEP_SUMMARY env var holds a file to append markdown to; locally it
-- is unset, so this is a no-op. (Parenthesised return truncates gsub's
-- extra count value; no literal backticks here by design.)
local summaryPath = os.getenv('GITHUB_STEP_SUMMARY')
if summaryPath and summaryPath ~= '' then
    local f = io.open(summaryPath, 'a')
    if f then
        local function md(s)
            return (tostring(s):gsub('[%c]', ' '):gsub('|', '\\|'))
        end
        f:write(('## qb-emsjob test suite — %s\n\n'):format(_VERSION))
        f:write('| Result | Test |\n|---|---|\n')
        for _, t in ipairs(tests) do
            if t.ok then
                f:write(('| ✅ | %s |\n'):format(md(t.name)))
            else
                f:write(('| ❌ | %s — %s |\n'):format(md(t.name), md(t.err)))
            end
        end
        f:write(('\n**%d passed, %d failed**\n'):format(#tests - failed, failed))
        f:close()
    end
end

if failed > 0 then
    os.exit(1)
end
