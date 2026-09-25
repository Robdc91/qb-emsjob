--[[
    qb-emsjob | tests/fivem_stubs.lua
    Minimal FiveM environment stubs so the real server logic can run under
    plain Lua 5.4. Loaded by run_tests.lua before any resource file.

    Provides: vector3/vec3/vec4, event registry + fireEvent, QBCore stub,
    MySQL stub backed by an in-memory DB, ped/coords/health natives, an
    event log for assertions, plus client-side stubs: LocalPlayer statebag,
    NUI bridge (SendNUIMessage / SetNuiFocus / RegisterNUICallback) and
    TriggerServerEvent — enough to run client/duty_menu.lua under test.
]]

local M = {}

 ---------------------------------------------------------------------------
 -- vector3 / vec3 / vec4
 ---------------------------------------------------------------------------

local vecmt = {}

vecmt.__index = vecmt

function vecmt.__sub(a, b)
    return M.vector3(a.x - b.x, a.y - b.y, a.z - b.z)
end

function vecmt.__len(v)
    return math.sqrt(v.x ^ 2 + v.y ^ 2 + v.z ^ 2)
end

function vecmt.__eq(a, b)
    return a.x == b.x and a.y == b.y and a.z == b.z
end

function vecmt.__tostring(v)
    return ('vector3(%s, %s, %s)'):format(v.x, v.y, v.z)
end

function M.vector3(x, y, z)
    return setmetatable({ x = x + 0.0, y = y + 0.0, z = z + 0.0 }, vecmt)
end

M.vec3 = M.vector3

function M.vec4(x, y, z, w)
    local v = M.vector3(x, y, z)
    v.w = w + 0.0
    return v
end

-- Globals as FiveM exposes them (config.lua calls vec3/vec4 directly)
vector3 = M.vector3
vec3 = M.vector3
vec4 = M.vec4
Vector3 = M.vector3
Vector4 = M.vec4

 ---------------------------------------------------------------------------
 -- Event registry
 ---------------------------------------------------------------------------

M.handlers = {}   -- [eventName] = { fn, ... }
M.eventLog = {}   -- { { name = ..., source = ..., args = {...} }, ... }

function M.RegisterNetEvent(name, fn)
    M.handlers[name] = M.handlers[name] or {}
    table.insert(M.handlers[name], fn)
end

M.AddEventHandler = M.RegisterNetEvent

-- Globals: server scripts register handlers with these
RegisterNetEvent = M.RegisterNetEvent
AddEventHandler = M.AddEventHandler

--- Fire a registered handler as the server would, setting the magic `source`.
function M.fireEvent(name, source, ...)
    local list = M.handlers[name]
    if not list then return false end

    local prev = _G.source
    _G.source = source
    for _, fn in ipairs(list) do
        fn(...)
    end
    _G.source = prev or 0

    M.eventLog[#M.eventLog + 1] = { name = name, source = source, args = { ... } }
    return true
end

 ---------------------------------------------------------------------------
 -- Remote trigger stubs (recorded for assertions)
 ---------------------------------------------------------------------------

local function record(name, target, ...)
    M.eventLog[#M.eventLog + 1] = { name = name, target = target, args = { ... } }
end

-- Globals: server code calls TriggerClientEvent / TriggerEvent directly.
-- TriggerClientEvent records the send AND delivers it to any registered
-- client handler: FiveM would network the event to that client, and here
-- everything runs in one process, so delivery is immediate.
function TriggerClientEvent(name, target, ...)
    record(name, target, ...)
    local list = M.handlers[name]
    if list then
        for _, fn in ipairs(list) do
            fn(...)
        end
    end
end

function TriggerEvent(name, ...)
    record(name, nil, ...)
end

 ---------------------------------------------------------------------------
 -- QBCore stub
 ---------------------------------------------------------------------------

M.players = {}          -- [source] = Player object
M.callbacks = {}        -- [name] = fn
M.useableItems = {}     -- [itemName] = fn

local function makePlayer(source, data)
    data.PlayerData.source = source
    local Player = {
        PlayerData = data.PlayerData,
        Functions = {},
    }

    function Player.Functions.RemoveMoney(account, amount, reason)
        local money = Player.PlayerData.money
        if (money[account] or 0) < amount then return false end
        money[account] = money[account] - amount
        return true
    end

    function Player.Functions.GetItemByName(item)
        return Player.PlayerData.items[item]
    end

    function Player.Functions.RemoveItem(item, count)
        local inv = Player.PlayerData.items
        if not inv[item] or (inv[item].amount or 0) < count then return false end
        inv[item].amount = inv[item].amount - count
        if inv[item].amount <= 0 then inv[item] = nil end
        return true
    end

    function Player.Functions.SetJobDuty(state)
        Player.PlayerData.job.onduty = state
    end

    return Player
end

--- Register a fake player. opts: job, grade, onduty, bank, cash, items, name
function M.addPlayer(source, opts)
    opts = opts or {}
    local data = {
        PlayerData = {
            citizenid = opts.citizenid or ('CID%s'):format(source),
            name = opts.name or ('Player%s'):format(source),
            job = {
                name = opts.job or 'unemployed',
                label = opts.jobLabel or 'Civilian',
                onduty = opts.onduty == true,
                grade = { level = opts.grade or 0 },
            },
            money = {
                bank = opts.bank or 0,
                cash = opts.cash or 0,
            },
            items = opts.items or {},
            charinfo = { firstname = opts.firstname or 'John', lastname = opts.lastname or 'Doe' },
        },
    }
    M.players[source] = makePlayer(source, data)
    return M.players[source]
end

local QBCoreStub = {
    Functions = {},
    Shared = { Items = {} },
}

function QBCoreStub.Functions.GetPlayer(source)
    return M.players[tonumber(source)]
end

function QBCoreStub.Functions.GetQBPlayers()
    return M.players
end

function QBCoreStub.Functions.CreateCallback(name, fn)
    M.callbacks[name] = fn
end

function QBCoreStub.Functions.CreateUseableItem(item, fn)
    M.useableItems[item] = fn
end

-- Client side: QBCore.Functions.TriggerCallback(name, cb | data, cb) fires
-- the server-registered callback. The real framework supplies the requesting
-- client's source as the callback's first arg; the stub uses M.localSource
-- (set per test, nil = no local player known to the server).
function QBCoreStub.Functions.TriggerCallback(name, a, b)
    local cb = type(a) == 'function' and a or b
    local fn = M.callbacks[name]
    if not fn then error(('no callback registered: %s'):format(tostring(name))) end
    fn(M.localSource, cb)
end

function QBCoreStub.Functions.Notify(msg, ntype, length)
    M.notifyLog = M.notifyLog or {}
    M.notifyLog[#M.notifyLog + 1] = { msg = msg, ntype = ntype, length = length }
end

M.QBCore = QBCoreStub

 ---------------------------------------------------------------------------
 -- exports stub ( both exports['qb-core']:GetCoreObject() and exports('x', fn) )
 ---------------------------------------------------------------------------

M.currentResource = 'qb-emsjob'
M.resourceExports = {
    ['qb-core'] = { GetCoreObject = function() return QBCoreStub end },
}

-- exports('Name', fn) inside a resource registers a named export.
-- Consuming code does exports[resource]:Name(...); the colon call passes the
-- proxy table as the first arg, which FiveM's native layer strips — so the
-- stub wraps every export to drop a leading table argument.
local function wrapExport(fn, proxyTable)
    return function(first, ...)
        if first == proxyTable then
            return fn(...)
        end
        return fn(first, ...)
    end
end

exports = setmetatable({}, {
    __call = function(_, name, fn)
        local res = M.resourceExports[M.currentResource] or {}
        M.resourceExports[M.currentResource] = res
        res[name] = wrapExport(fn, res)
    end,
    __index = function(_, k)
        M.resourceExports[k] = M.resourceExports[k] or {}
        return M.resourceExports[k]
    end,
})

--- Manually register a named export: exports[res]:Name(...)
function M.registerExport(resource, name, fn)
    M.resourceExports[resource] = M.resourceExports[resource] or {}
    M.resourceExports[resource][name] = fn
end

 ---------------------------------------------------------------------------
 -- MySQL stub (in-memory insurance DB)
 ---------------------------------------------------------------------------

M.db = {
    insurance = {},  -- [citizenid] = { active = bool, expires = 'YYYY-MM-DD'|nil }
}

MySQL = {
    single = {},
    update = {},
    insert = {},
}

-- oxmysql calls these with a dot: MySQL.single.await(query, params)
MySQL.single.await = function(query, params)
    if query:find('player_insurance') then
        local cid = params and params[1]
        local row = M.db.insurance[cid]
        if row then
            return { active = row.active, expires = row.expires }
        end
        return nil
    end
    return nil
end

MySQL.update.await = function(query, params)
    if query:find('player_insurance') then
        local cid = params and params[2]
        local row = M.db.insurance[cid]
        if row then row.active = params[1] == true or params[1] == 1 end
        return 1
    end
    return 0
end

MySQL.insert.await = function(query, params)
    M.insertLog = M.insertLog or {}
    M.insertLog[#M.insertLog + 1] = { query = query, params = params }
    return 1
end

 ---------------------------------------------------------------------------
 -- Ped / entity natives
 ---------------------------------------------------------------------------

M.peds = {} -- [source] = { coords = vector3, health = number }

function M.setPed(source, coords, health)
    M.peds[source] = { coords = coords or M.vector3(0, 0, 0), health = health or 200 }
end

function GetPlayerPed(source)
    return tonumber(source) or 0
end

function GetEntityCoords(pedHandle)
    local p = M.peds[pedHandle]
    if p then return p.coords end
    return M.vector3(0, 0, 0)
end

function GetEntityHealth(pedHandle)
    local p = M.peds[pedHandle]
    return p and p.health or 200
end

function GetPlayerName(source)
    local p = M.players[tonumber(source)]
    return p and p.PlayerData.name or 'Unknown'
end

 ---------------------------------------------------------------------------
 -- Vehicles + local ped (client/garage.lua)
 ---------------------------------------------------------------------------

M.vehicles = {}          -- [handle] = { model, class, plate, heading, engineOn, fuel }
M.deletedVehicles = {}   -- handles passed to DeleteVehicle
M.spawnLog = {}          -- SpawnVehicle calls: { model, coords, network, veh }
M.pedInVehicle = 0       -- GetVehiclePedIsIn result for the local ped
M.warped = nil           -- TaskWarpPedIntoVehicle call

local nextVehicleId = 500

function PlayerPedId()
    return tonumber(M.localSource) or 1
end

function GetVehiclePedIsIn(ped, lastVeh)
    return M.pedInVehicle or 0
end

function GetEntityModel(veh)
    local v = M.vehicles[veh]
    return v and v.model or 0
end

function GetVehicleClass(veh)
    local v = M.vehicles[veh]
    return v and v.class or 0
end

function DeleteVehicle(veh)
    M.deletedVehicles[#M.deletedVehicles + 1] = veh
    M.vehicles[veh] = nil
end

function SetEntityHeading(veh, heading)
    local v = M.vehicles[veh]
    if v then v.heading = heading + 0.0 end
end

function SetVehicleNumberPlateText(veh, plate)
    local v = M.vehicles[veh]
    if v then v.plate = plate end
end

function SetVehicleDirtLevel() end

function SetVehicleEngineOn(veh, on)
    local v = M.vehicles[veh]
    if v then v.engineOn = on == true end
end

function SetVehicleEngineHealth() end
function SetVehicleBodyHealth() end

function SetVehicleFuelLevel(veh, fuel)
    local v = M.vehicles[veh]
    if v then v.fuel = fuel + 0.0 end
end

function SetVehicleLivery(veh, livery)
    local v = M.vehicles[veh]
    if v then v.livery = livery end
end

function TaskWarpPedIntoVehicle(ped, veh, seat)
    M.warped = { ped = ped, veh = veh, seat = seat }
end

-- Client side of QBCore.Functions.SpawnVehicle: create a fake vehicle,
-- record the call, then hand the handle to the setup callback.
function QBCoreStub.Functions.SpawnVehicle(model, cb, coords, network)
    nextVehicleId = nextVehicleId + 1
    local veh = nextVehicleId
    M.vehicles[veh] = { model = joaat(model), class = 0, plate = 'NEW' .. veh }
    M.spawnLog[#M.spawnLog + 1] = { model = model, coords = coords, network = network == true, veh = veh }
    cb(veh)
    return veh
end

function QBCoreStub.Functions.GetPlate(veh)
    local v = M.vehicles[veh]
    return v and v.plate or ''
end

 ---------------------------------------------------------------------------
 -- Misc natives / globals
 ---------------------------------------------------------------------------

--- CreateThread runs the body as a coroutine: it executes until the first
--- Wait() and then suspends, so load-time loop threads (e.g. the client
--- interaction loops) park instead of hanging the test process.
M.threads = {}

function CreateThread(fn)
    local co = coroutine.create(fn)
    M.threads[#M.threads + 1] = co
    local ok, err = coroutine.resume(co)
    if not ok then error(err, 0) end
end

--- Yield the calling thread (FiveM semantics); resumable via M.resumeThreads().
function Wait(ms)
    coroutine.yield(ms)
end

function GetGameTimer()
    return math.floor(os.clock() * 1000)
end

--- Resume every suspended thread once (for future timer-stepping tests).
function M.resumeThreads()
    for _, co in ipairs(M.threads) do
        if coroutine.status(co) == 'suspended' then
            local ok, err = coroutine.resume(co)
            if not ok then error(err, 0) end
        end
    end
end

function GetConvar(name, default)
    return default
end

function joaat(str)
    local hash = 2166136261
    for i = 1, #str do
        hash = (hash ~ str:byte(i)) * 16777619
        hash = hash % 4294967296
    end
    return hash
end

GetCurrentResourceName = function() return 'qb-emsjob' end

 ---------------------------------------------------------------------------
 -- Client-side stubs: statebag, NUI bridge, server events
 -- (client/duty_menu.lua needs LocalPlayer.state, SendNUIMessage,
 --  SetNuiFocus, RegisterNUICallback and TriggerServerEvent)
 ---------------------------------------------------------------------------

M.nuiMessages = {}      -- { action = ..., state = ..., roster = ... }
M.nuiCallbacks = {}     -- [name] = fn(data, cb)
M.nuiFocus = { focused = false, keepInput = false }
M.serverEvents = {}     -- TriggerServerEvent log: { name = ..., args = {...} }

--- Fake player statebag: plain key/value reads plus the statebag :set API.
-- `set` takes self first so LocalPlayer.state:set(k, v, true) works.
local statebag = {}

M.statebagLog = {}

LocalPlayer = { state = setmetatable({
    set = function(_, key, value, replicated)
        statebag[key] = value
        M.statebagLog[#M.statebagLog + 1] = { key = key, value = value, replicated = replicated == true }
    end,
}, {
    __index = function(_, k) return statebag[k] end,
    __newindex = function(_, k, v) statebag[k] = v end,
}) }

function TriggerServerEvent(name, ...)
    M.serverEvents[#M.serverEvents + 1] = { name = name, args = { ... } }
end

function SendNUIMessage(msg)
    M.nuiMessages[#M.nuiMessages + 1] = msg
end

function SetNuiFocus(focused, keepInput)
    M.nuiFocus = { focused = focused == true, keepInput = keepInput == true }
end

function RegisterNUICallback(name, fn)
    M.nuiCallbacks[name] = fn
end

--- Call a registered NUI callback the way the UI would.
function M.invokeNui(name, data)
    local fn = M.nuiCallbacks[name]
    if not fn then error(('no NUI callback registered: %s'):format(tostring(name))) end

    local responded = nil
    fn(data, function(resp) responded = resp end)
    return responded
end

--- qb-target zone stubs: record registered zones (name -> options) so tests
--- can invoke zone option actions. registerExport does NOT colon-strip, so
--- these take the proxy table as a leading _ argument.
M.zones = {}          -- [name] = { coords, length, width, options, distance }
M.removedZones = {}   -- names passed to RemoveZone

M.registerExport('qb-target', 'AddBoxZone', function(_, name, coords, length, width, opts, options)
    M.zones[name] = {
        coords = coords,
        length = length,
        width = width,
        options = options and options.options or {},
        distance = options and options.distance or nil,
    }
end)

M.registerExport('qb-target', 'RemoveZone', function(_, name)
    M.removedZones[#M.removedZones + 1] = name
    M.zones[name] = nil
end)

 ---------------------------------------------------------------------------
 -- Blip natives + timers: the client DownedAlert handler runs when the
 -- server alert is delivered in-process via TriggerClientEvent, and it
 -- creates/flashes/labels a blip and schedules a removal timeout.
 ---------------------------------------------------------------------------

M.blips = {}
M.timers = {}

local nextBlipId = 1000

function AddBlipForCoord(x, y, z)
    nextBlipId = nextBlipId + 1
    M.blips[nextBlipId] = { x = x, y = y, z = z }
    return nextBlipId
end

function DoesBlipExist(blip) return M.blips[blip] ~= nil end
function RemoveBlip(blip) M.blips[blip] = nil end
function SetBlipSprite() end
function SetBlipDisplay() end
function SetBlipScale() end
function SetBlipColour() end
function SetBlipFlashes() end
function SetBlipAsShortRange() end
function BeginTextCommandSetBlipName() end
function AddTextComponentSubstringPlayerName() end
function EndTextCommandSetBlipName() end

function SetTimeout(ms, fn)
    M.timers[#M.timers + 1] = { ms = ms, fn = fn }
end

-- Draw / input natives used by client draw loops and blip refresh
function SetBlipAlpha(blip, alpha)
    local b = M.blips[blip]
    if b then b.alpha = alpha end
end

function IsPedInAnyVehicle(ped, atGetIn)
    return (M.pedInVehicle or 0) ~= 0
end

function IsControlJustReleased(pad, control) return false end

function SetTextScale() end
function SetTextFont() end
function SetTextProportional() end
function SetTextColour() end
function SetTextEntry() end
function SetTextCentre() end
function AddTextComponentString() end
function SetDrawOrigin() end
function DrawText() end
function DrawRect() end
function ClearDrawOrigin() end

 ---------------------------------------------------------------------------
 -- Reset between tests
 ---------------------------------------------------------------------------

function M.reset()
    M.players = {}
    M.eventLog = {}
    M.insertLog = nil
    M.db.insurance = {}
    M.peds = {}
    M.threads = {}
    M.blips = {}
    M.timers = {}
    M.vehicles = {}
    M.deletedVehicles = {}
    M.spawnLog = {}
    M.pedInVehicle = 0
    M.warped = nil
    M.zones = {}
    M.removedZones = {}
    M.nuiMessages = {}
    -- NOTE: nuiCallbacks intentionally survive reset, like M.callbacks and
    -- M.useableItems: load-time RegisterNUICallback registrations must keep
    -- working after setup() (e.g. the duty menu 'close' used to reset state).
    M.nuiFocus = { focused = false, keepInput = false }
    M.serverEvents = {}
    M.statebagLog = {}
    M.notifyLog = nil
    M.localSource = nil
    statebag['emsStatus'] = nil
    statebag['emsCallsign'] = nil
    _G.source = 0
end

M.reset()

return M
