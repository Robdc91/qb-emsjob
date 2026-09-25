--[[
    qb-emsjob | client/target_bridge.lua
    Framework bridge for interaction targets.

    Picks the first available targeting resource at call time:
      1. qb-target  (QBCore stacks)
      2. ox_target  (Qbox / overextended stacks)
    and maps qb-target's call shapes onto ox_target's API. When neither is
    present, callers should fall back to 3D text (duty points already do).

    Globals defined here (loaded first in client_scripts):
      TargetAddBoxZone(name, coords, length, width, targetOpts, options)
      TargetRemoveZone(name)
      TargetAddEntity(ped, options)      -- options: qb-target shape
      TargetRemoveEntity(ped)

    Detection goes through the shared bridge.lua (Bridge.IsStarted).
]]

local oxZoneIds = {}   -- [name] = ox_target zone id
local oxEntityIds = {} -- [ped]  = ox_target local-entity id

--- Active backend: 'qb' | 'ox' | nil (neither started).
-- Cached after the first call: target resources do not change mid-session.
-- TargetBridgeReset() re-arms detection (test hook; harmless in production).
local backend

function TargetBridgeReset()
    backend = nil
    oxZoneIds = {}
    oxEntityIds = {}
    Bridge.ResetCaches()
end

local function pickBackend()
    if backend == nil then
        if Bridge.IsStarted('qb-target') then
            backend = 'qb'
        elseif Bridge.IsStarted('ox_target') then
            backend = 'ox'
        else
            backend = false -- neither present; warn once, no-op below
            print('^3[qb-emsjob]^7 Neither qb-target nor ox_target is started - interaction points are disabled. Set Config.UseTarget = false to use 3D text instead.')
        end
    end
    return backend
end

--- Map one qb-target option to an ox_target option.
local function toOxOption(opt, distance)
    return {
        label = opt.label,
        icon = opt.icon,
        groups = opt.job,
        canInteract = opt.canInteract,
        onSelect = opt.action,
        distance = distance,
    }
end

function TargetAddBoxZone(name, coords, length, width, targetOpts, options)
    local b = pickBackend()
    if b == 'qb' then
        exports['qb-target']:AddBoxZone(name, coords, length, width, targetOpts, options)
        return
    elseif b ~= 'ox' then
        return
    end

    local oxOptions = {}
    for _, opt in ipairs(options and options.options or {}) do
        oxOptions[#oxOptions + 1] = toOxOption(opt, options and options.distance or nil)
    end

    local id = exports.ox_target:addBoxZone({
        coords = coords,
        size = vec3(length or 2.0, width or 2.0, 3.0),
        rotation = targetOpts and targetOpts.heading or 0,
        debug = targetOpts and targetOpts.debugPoly or false,
        options = oxOptions,
    })
    oxZoneIds[name] = id
end

function TargetRemoveZone(name)
    local b = pickBackend()
    if b == 'qb' then
        exports['qb-target']:RemoveZone(name)
        return
    elseif b ~= 'ox' then
        return
    end

    local id = oxZoneIds[name]
    if id then
        exports.ox_target:removeZone(id)
        oxZoneIds[name] = nil
    end
end

function TargetAddEntity(ped, config)
    local b = pickBackend()
    if b == 'qb' then
        exports['qb-target']:AddTargetEntity(ped, config)
        return
    elseif b ~= 'ox' then
        return
    end

    local oxOptions = {}
    for _, opt in ipairs(config and config.options or {}) do
        oxOptions[#oxOptions + 1] = toOxOption(opt, config and config.distance or nil)
    end
    oxEntityIds[ped] = exports.ox_target:addLocalEntity(ped, oxOptions)
end

function TargetRemoveEntity(ped)
    local b = pickBackend()
    if b == 'qb' then
        exports['qb-target']:RemoveTargetEntity(ped)
        return
    elseif b ~= 'ox' then
        return
    end

    local id = oxEntityIds[ped]
    if id then
        exports.ox_target:removeLocalEntity(id)
        oxEntityIds[ped] = nil
    end
end
