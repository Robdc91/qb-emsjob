--[[
    qb-emsjob | client/revive.lua
    Death / last-stand handling, EMS revive & heal interactions, self-heal items.
]]

local QBCore = exports['qb-core']:GetCoreObject()

local laststandThreadActive = false
local downedBlip = nil
local respawnHoldStart = 0

 ---------------------------------------------------------------------------
 -- Helpers
 ---------------------------------------------------------------------------

local function loadAnimDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
end

local function isSelfDowned()
    local st = LocalPlayer.state
    return (st.laststand ~= nil and st.laststand ~= false) or (st.isdead == true)
end

--- Read another player's downed state via replicated statebags.
local function isPlayerDowned(serverId)
    local ok, st = pcall(function() return Player(serverId).state end)
    if not ok or not st then return false end
    return (st.laststand ~= nil and st.laststand ~= false) or (st.isdead == true)
end

local function clearDownedBlip()
    if downedBlip and DoesBlipExist(downedBlip) then
        RemoveBlip(downedBlip)
    end
    downedBlip = nil
end

local function restorePed(health)
    local ped = PlayerPedId()
    clearDownedBlip()

    -- A fully dead ped needs a proper resurrection before health can be set
    if IsEntityDead(ped) then
        local coords = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
        ped = PlayerPedId()
    end

    StopAnimTask(ped, 'dead', 'dead_a', 1.0)
    ClearPedTasks(ped)
    SetEntityInvincible(ped, false)
    SetEntityHealth(ped, health or 200)

    if Config.RemoveWeaponAfterDeath then
        RemoveAllPedWeapons(ped, true)
        for _, weapon in ipairs(Config.WeaponsToKeep or {}) do
            local hash = type(weapon) == 'string' and joaat(weapon:lower()) or weapon
            GiveWeaponToPed(ped, hash, 100, false, true)
        end
    end
end

 ---------------------------------------------------------------------------
 -- Death / last stand
 ---------------------------------------------------------------------------

local function enterLaststand()
    if laststandThreadActive then return end
    laststandThreadActive = true

    local ped = PlayerPedId()
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
    loadAnimDict('dead')
    TaskPlayAnim(ped, 'dead', 'dead_a', 8.0, 8.0, -1, 9, 0, false, false, false)

    LocalPlayer.state:set('laststand', Config.LaststandTimer, true)

    -- One-time alert to on-duty EMS
    TriggerServerEvent('qb-emsjob:server:PlayerDowned', GetEntityCoords(ped))

    -- Blinking blip on own position (visible to self)
    downedBlip = AddBlipForCoord(GetEntityCoords(ped))
    SetBlipSprite(downedBlip, 153)
    SetBlipColour(downedBlip, 1)
    SetBlipScale(downedBlip, 1.0)
    SetBlipFlashes(downedBlip, true)

    -- Countdown thread
    CreateThread(function()
        local remaining = Config.LaststandTimer
        local notified = {}

        while remaining > 0 and isSelfDowned() and not LocalPlayer.state.isdead do
            LocalPlayer.state:set('laststand', remaining, true)

            if math.floor(remaining / 30) ~= notified.lastBucket then
                notified.lastBucket = math.floor(remaining / 30)
                if remaining <= 30 or remaining % 30 == 0 then
                    EMSNotify(_L('laststand', { seconds = remaining }), 'error', 3000)
                end
            end

            Wait(1000)
            remaining = remaining - 1
        end

        if LocalPlayer.state.isdead then return end

        if isSelfDowned() then
            -- Bled out -> fully dead
            LocalPlayer.state:set('laststand', false, true)
            LocalPlayer.state:set('isdead', true, true)
            respawnHoldStart = 0
        end
    end)

    -- Bleeding-out HUD
    CreateThread(function()
        while isSelfDowned() and not LocalPlayer.state.isdead do
            Wait(0)
            local st = LocalPlayer.state.laststand
            if type(st) == 'number' and st > 0 then
                DrawText3D(GetEntityCoords(PlayerPedId()).x, GetEntityCoords(PlayerPedId()).y, GetEntityCoords(PlayerPedId()).z + 1.0, _L('laststand', { seconds = st }))
            end
        end
    end)

    laststandThreadActive = false
end

--- Nearest configured hospital by straight-line distance.
function GetNearestHospital()
    local pos = GetEntityCoords(PlayerPedId())
    local best, bestDist = nil, math.huge
    for _, h in ipairs(Config.Hospitals) do
        local d = #(pos - h.blip)
        if d < bestDist then
            best, bestDist = h, d
        end
    end
    return best
end

local function respawnAtHospital()
    LocalPlayer.state:set('laststand', false, true)
    LocalPlayer.state:set('isdead', false, true)

    local hospital = GetNearestHospital()
    local pos = hospital and hospital.respawn or Config.Hospitals[1].respawn
    DoScreenFadeOut(500)
    Wait(500)
    restorePed(150)
    SetEntityCoords(PlayerPedId(), pos.x, pos.y, pos.z, false, false, false, false)
    SetEntityHeading(PlayerPedId(), pos.w or 0.0)
    Wait(500)
    DoScreenFadeIn(500)
    TriggerServerEvent('qb-emsjob:server:RespawnBilled')
end

CreateThread(function()
    while true do
        local sleep = 500
        if isLoggedIn then
            local ped = PlayerPedId()
            if IsEntityDead(ped) and not isSelfDowned() then
                if Config.LaststandEnabled then
                    enterLaststand()
                else
                    LocalPlayer.state:set('isdead', true, true)
                    respawnHoldStart = 0
                end
                sleep = 1000
            elseif LocalPlayer.state.isdead then
                sleep = 0
                -- Hold E to respawn at the hospital
                DrawText3D(GetEntityCoords(ped).x, GetEntityCoords(ped).y, GetEntityCoords(ped).z + 1.0, 'Hold [E] to respawn')
                if IsControlPressed(0, 38) then
                    if respawnHoldStart == 0 then respawnHoldStart = GetGameTimer() end
                    if GetGameTimer() - respawnHoldStart > 3000 then
                        respawnHoldStart = 0
                        respawnAtHospital()
                    end
                else
                    respawnHoldStart = 0
                end
            end
        end
        Wait(sleep)
    end
end)

 ---------------------------------------------------------------------------
 -- EMS interactions with other players
 ---------------------------------------------------------------------------

local function startRevive(serverId)
    if not CanPerformEMS() then
        EMSNotify(_L('wrong_job'), 'error')
        return
    end
    if (PlayerJob.grade and PlayerJob.grade.level or 0) < Config.MinGradeToRevive then
        EMSNotify(_L('no_permission'), 'error')
        return
    end
    if not isPlayerDowned(serverId) then
        EMSNotify(_L('no_players_nearby'), 'error')
        return
    end

    local targetPed = GetPlayerPed(GetPlayerFromServerId(serverId))
    if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(targetPed)) > Config.ReviveDistance + 1.5 then
        return
    end

    EMSNotify(_L('reviving', { name = GetPlayerName(GetPlayerFromServerId(serverId)) }), 'primary')
    if not ProgressBar(_L('progress_revive'), Config.ReviveTime, 'mini@cpr@char_a@cpr_str', 'cpr_success') then
        return
    end

    TriggerServerEvent('qb-emsjob:server:RevivePlayer', serverId)
end

local function startHeal(serverId)
    if not CanPerformEMS() then
        EMSNotify(_L('wrong_job'), 'error')
        return
    end
    if (PlayerJob.grade and PlayerJob.grade.level or 0) < Config.MinGradeToHeal then
        EMSNotify(_L('no_permission'), 'error')
        return
    end
    if isPlayerDowned(serverId) then
        startRevive(serverId)
        return
    end

    local targetPed = GetPlayerPed(GetPlayerFromServerId(serverId))
    if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(targetPed)) > Config.ReviveDistance + 1.5 then
        return
    end

    if not ProgressBar(_L('progress_heal'), Config.HealTime, 'mini@cpr@char_a@cpr_str', 'cpr_paddlechest') then
        return
    end

    TriggerServerEvent('qb-emsjob:server:HealPlayer', serverId)
end

local function startCheckup(serverId)
    if not CanPerformEMS() then return end
    TriggerServerEvent('qb-emsjob:server:CheckupPlayer', serverId)
end

-- Dynamically attach/detach qb-target options to nearby downed players.
local trackedPeds = {}

CreateThread(function()
    while true do
        local sleep = 1000
        if isLoggedIn and IsEMS() and OnDuty then
            sleep = 700
            local myCoords = GetEntityCoords(PlayerPedId())
            local activePeds = {}

            for _, player in ipairs(GetActivePlayers()) do
                local ped = GetPlayerPed(player)
                if ped ~= PlayerPedId() and DoesEntityExist(ped) then
                    local sid = GetPlayerServerId(player)
                    local downed = isPlayerDowned(sid)
                    local near = #(myCoords - GetEntityCoords(ped)) < 15.0

                    if near and (downed or Config.EnableCheckup) then
                        activePeds[ped] = true
                        if not trackedPeds[ped] then
                            trackedPeds[ped] = true
                            exports['qb-target']:AddTargetEntity(ped, {
                                options = {
                                    {
                                        label = _L('target_revive'),
                                        icon = 'fas fa-heart-pulse',
                                        job = Config.JobName,
                                        canInteract = function() return isPlayerDowned(sid) end,
                                        action = function() startRevive(sid) end,
                                    },
                                    {
                                        label = _L('target_heal'),
                                        icon = 'fas fa-kit-medical',
                                        job = Config.JobName,
                                        canInteract = function() return not isPlayerDowned(sid) end,
                                        action = function() startHeal(sid) end,
                                    },
                                    {
                                        label = _L('target_checkup'),
                                        icon = 'fas fa-stethoscope',
                                        job = Config.JobName,
                                        action = function() startCheckup(sid) end,
                                    },
                                },
                                distance = Config.ReviveDistance,
                            })
                        end
                    end
                end
            end

            -- Clean up stale entries
            for ped in pairs(trackedPeds) do
                if not activePeds[ped] or not DoesEntityExist(ped) then
                    exports['qb-target']:RemoveTargetEntity(ped)
                    trackedPeds[ped] = nil
                end
            end
        end
        Wait(sleep)
    end
end)

 ---------------------------------------------------------------------------
 -- Apply revive / heal on self (triggered by server after validation)
 ---------------------------------------------------------------------------

RegisterNetEvent('qb-emsjob:client:Revived', function(amount)
    LocalPlayer.state:set('laststand', false, true)
    LocalPlayer.state:set('isdead', false, true)
    restorePed(200)
    if amount and amount > 0 then
        EMSNotify(_L('revived', { amount = amount }), 'success', 7500)
    else
        EMSNotify(_L('revived', { amount = 0 }), 'success', 7500)
    end
end)

RegisterNetEvent('qb-emsjob:client:Healed', function(amount)
    restorePed(200)
    EMSNotify(_L('healed', { amount = amount or 0 }), 'success')
end)

RegisterNetEvent('qb-emsjob:client:SendVitals', function(hp, insured)
    if insured then
        EMSNotify(_L('checkup_insured', { hp = hp }), 'success')
    else
        EMSNotify(_L('checkup_info', { hp = hp }), 'primary')
    end
end)

 ---------------------------------------------------------------------------
 -- Self-heal items (useable items registered server-side)
 ---------------------------------------------------------------------------

local selfHealReady = 0

RegisterNetEvent('qb-emsjob:client:UseBandage', function()
    if isSelfDowned() then
        EMSNotify(_L('no_self_heal'), 'error')
        return
    end
    if GetGameTimer() < selfHealReady then
        EMSNotify(_L('cooldown', { seconds = math.ceil((selfHealReady - GetGameTimer()) / 1000) }), 'error')
        return
    end

    if not ProgressBar(_L('progress_selfheal'), 5000, 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', 'machinic_loop_mechandplayer') then
        return
    end

    local ped = PlayerPedId()
    local maxHealth = GetEntityMaxHealth(ped)
    SetEntityHealth(ped, math.min(maxHealth, GetEntityHealth(ped) + 30))
    selfHealReady = GetGameTimer() + (Config.SelfHealCooldownSeconds * 1000)
    EMSNotify(_L('self_heal_used'), 'success')
end)

RegisterNetEvent('qb-emsjob:client:UseIfaks', function()
    if isSelfDowned() then
        EMSNotify(_L('no_self_heal'), 'error')
        return
    end
    if GetGameTimer() < selfHealReady then
        EMSNotify(_L('cooldown', { seconds = math.ceil((selfHealReady - GetGameTimer()) / 1000) }), 'error')
        return
    end

    if not ProgressBar(_L('progress_selfheal'), 8000, 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', 'machinic_loop_mechandplayer') then
        return
    end

    SetEntityHealth(PlayerPedId(), GetEntityMaxHealth(PlayerPedId()))
    selfHealReady = GetGameTimer() + (Config.SelfHealCooldownSeconds * 1000)
    EMSNotify(_L('self_heal_used'), 'success')
end)

 ---------------------------------------------------------------------------
 -- Cleanup
 ---------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearDownedBlip()
    for ped in pairs(trackedPeds) do
        if DoesEntityExist(ped) then
            exports['qb-target']:RemoveTargetEntity(ped)
        end
    end
end)
