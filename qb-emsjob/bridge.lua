--[[
    qb-emsjob | bridge.lua (shared)
    Single detection helper for optional framework resources. Runs in BOTH
    the client and server VMs (shared_scripts), so client code (target
    bridge, garage picker) and server code (items, billing) share one
    implementation instead of repeating GetResourceState checks.

    Globals defined here:
      Bridge.IsStarted(resource)  -- true when the resource is running
      Bridge.GetOxLib()           -- ox_lib module table or nil (cached)
      Bridge.ResetCaches()        -- test hook: re-arm all cached detection
]]

Bridge = {}

function Bridge.IsStarted(resource)
    return GetResourceState(resource) == 'started'
end

local oxLib = false -- false = not resolved yet; nil = resolved, unavailable

--- Resolve the ox_lib module. The `lib` global only exists in this resource
--- when its init.lua was imported (qb-emsjob does not import it), so fall
--- back to a cross-resource require (FiveM lua54). nil = no usable ox_lib.
function Bridge.GetOxLib()
    if oxLib == false then
        if type(lib) == 'table' then
            oxLib = lib
        else
            local ok, mod = pcall(require, '@ox_lib/init.lua')
            oxLib = (ok and type(mod) == 'table') and mod or nil
        end
    end
    return oxLib
end

--- Test hook: re-arm cached detection (harmless in production).
function Bridge.ResetCaches()
    oxLib = false
end
