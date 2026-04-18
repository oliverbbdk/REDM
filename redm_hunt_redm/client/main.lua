local State = {
    active = false,
    huntId = 0,
    targetServerId = nil,
    controllerServerId = nil,
    groupKey = nil,
    isController = false,
    config = nil,
    hunters = {},
    mounts = {},
    dismountRange = 24.0,
    groupSpreadRadius = 10.0,
    taskRefreshMs = 1500,
    targetDeadReported = false
}

local function cdebug(msg)
    if Config.Debug then
        print(('[hunt-client] %s'):format(msg))
    end
end

local function resetState()
    State.active = false
    State.huntId = 0
    State.targetServerId = nil
    State.controllerServerId = nil
    State.groupKey = nil
    State.isController = false
    State.config = nil
    State.hunters = {}
    State.mounts = {}
    State.dismountRange = 24.0
    State.groupSpreadRadius = 10.0
    State.taskRefreshMs = 1500
    State.targetDeadReported = false
end

local function loadModel(model)
    if not IsModelValid(model) then
        return false
    end

    RequestModel(model)
    local timeout = GetGameTimer() + 15000

    while not HasModelLoaded(model) do
        Wait(50)
        if GetGameTimer() > timeout then
            return false
        end
    end

    return true
end

local function randomItem(list)
    return list[math.random(1, #list)]
end

local function getGroundZ(x, y, zGuess)
    local found, z = GetGroundZFor_3dCoord(x, y, zGuess + 50.0, false)
    if found then
        return z
    end
    return zGuess
end

local function findGroupedSpawn(targetCoords, minDist, maxDist)
    for _ = 1, 20 do
        local angle = math.rad(math.random(0, 359))
        local dist = minDist + (math.random() * (maxDist - minDist))
        local sx = targetCoords.x + math.cos(angle) * dist
        local sy = targetCoords.y + math.sin(angle) * dist
        local sz = getGroundZ(sx, sy, targetCoords.z)
        return vector3(sx, sy, sz), dist
    end
    return nil, nil
end

local function makeOffset(origin, radius)
    local angle = math.rad(math.random(0, 359))
    local dist = math.random() * radius
    local x = origin.x + math.cos(angle) * dist
    local y = origin.y + math.sin(angle) * dist
    local z = getGroundZ(x, y, origin.z)
    return vector3(x, y, z)
end

local function safeDelete(ent)
    if ent and ent ~= 0 and DoesEntityExist(ent) then
        SetEntityAsMissionEntity(ent, true, true)
        DeleteEntity(ent)
    end
end

local function cleanupEntities()
    cdebug(('Cleanup start: hunters=%s mounts=%s'):format(#State.hunters, #State.mounts))

    for _, ped in ipairs(State.hunters) do
        safeDelete(ped)
    end

    for _, horse in ipairs(State.mounts) do
        safeDelete(horse)
    end

    State.hunters = {}
    State.mounts = {}
end

local function setCombatPed(ped, weaponHash, targetPed)
    if weaponHash and weaponHash ~= 0 then
        GiveWeaponToPed_2(ped, weaponHash, 200, true, true, 0, false, 0.5, 1.0, 752097756, false, 0, false)
        SetCurrentPedWeapon(ped, weaponHash, true, 0, false, false)
    end

    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAttributes(ped, 5, true)
    SetPedCombatAttributes(ped, 1, true)
    SetPedCombatAttributes(ped, 0, true)
    SetPedAccuracy(ped, 45)
    SetPedFleeAttributes(ped, 0, false)
    SetPedKeepTask(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskCombatPed(ped, targetPed, 0, 16)
end

local function setAnimalAttack(animal, targetPed)
    SetPedKeepTask(animal, true)
    SetBlockingOfNonTemporaryEvents(animal, true)
    TaskCombatPed(animal, targetPed, 0, 16)
end

local function mountPedOnHorse(rider, horse)
    Citizen.InvokeNative(0x028F76B6E78246EB, rider, horse, -1)
end

local function spawnGroup(data)
    local targetPlayer = GetPlayerFromServerId(data.target)
    if targetPlayer == -1 then
        cdebug(('Target unavailable on controller target=%s'):format(tostring(data.target)))
        TriggerServerEvent('redm_hunters:serverControllerFailed', data.huntId, 'target_not_streamed')
        return
    end

    local targetPed = GetPlayerPed(targetPlayer)
    if targetPed == 0 or not DoesEntityExist(targetPed) then
        cdebug('Target ped missing on controller')
        TriggerServerEvent('redm_hunters:serverControllerFailed', data.huntId, 'target_ped_missing')
        return
    end

    local targetCoords = GetEntityCoords(targetPed)
    local groupOrigin, spawnDist = findGroupedSpawn(targetCoords, data.minSpawnDistance, data.maxSpawnDistance)
    if not groupOrigin then
        cdebug('Failed to find group spawn')
        TriggerServerEvent('redm_hunters:serverControllerFailed', data.huntId, 'spawn_failed')
        return
    end

    cdebug(('Spawn group huntId=%s type=%s target=%s controller=%s origin=(%.2f, %.2f, %.2f) dist=%.2f')
        :format(data.huntId, data.groupKey, data.target, data.controller, groupOrigin.x, groupOrigin.y, groupOrigin.z, spawnDist))

    local report = {}

    for i = 1, data.config.count do
        local spawnPos = makeOffset(groupOrigin, data.groupSpreadRadius)
        local heading = math.random() * 360.0

        local pedModel = randomItem(data.config.pedModels)
        local horseModel = nil
        local weaponHash = 0

        if not data.config.animal and #data.config.weapons > 0 then
            weaponHash = randomItem(data.config.weapons)
        end

        if data.config.mounted and #data.config.horseModels > 0 then
            horseModel = randomItem(data.config.horseModels)
        end

        if not loadModel(pedModel) then
            cdebug(('Failed loading ped/animal model=%s'):format(tostring(pedModel)))
            goto continue
        end

        local mount = 0
        if horseModel then
            if not loadModel(horseModel) then
                cdebug(('Failed loading horse model=%s'):format(tostring(horseModel)))
                SetModelAsNoLongerNeeded(pedModel)
                goto continue
            end
        end

        if horseModel then
            mount = CreatePed(horseModel, spawnPos.x, spawnPos.y, spawnPos.z, heading, true, true, false, false)
            if mount ~= 0 then
                SetEntityAsMissionEntity(mount, true, true)
                table.insert(State.mounts, mount)
            end
        end

        local ped = CreatePed(pedModel, spawnPos.x, spawnPos.y, spawnPos.z, heading, true, true, false, false)
        if ped == 0 then
            cdebug(('Failed creating attacker i=%s model=%s'):format(i, tostring(pedModel)))
            if mount ~= 0 then
                safeDelete(mount)
            end
            SetModelAsNoLongerNeeded(pedModel)
            if horseModel then
                SetModelAsNoLongerNeeded(horseModel)
            end
            goto continue
        end

        SetEntityAsMissionEntity(ped, true, true)
        table.insert(State.hunters, ped)

        if mount ~= 0 and DoesEntityExist(mount) then
            mountPedOnHorse(ped, mount)
        end

        if data.config.animal then
            setAnimalAttack(ped, targetPed)
        else
            setCombatPed(ped, weaponHash, targetPed)
        end

        local pedNetId = NetworkGetNetworkIdFromEntity(ped)
        local mountNetId = mount ~= 0 and NetworkGetNetworkIdFromEntity(mount) or 0

        cdebug(('Spawned type=%s idx=%s pedModel=%s horseModel=%s pedNetId=%s horseNetId=%s pos=(%.2f, %.2f, %.2f)')
            :format(data.groupKey, i, tostring(pedModel), tostring(horseModel), tostring(pedNetId), tostring(mountNetId), spawnPos.x, spawnPos.y, spawnPos.z))

        report[#report + 1] = {
            index = i,
            pedModel = pedModel,
            horseModel = horseModel,
            pedNetId = pedNetId,
            horseNetId = mountNetId,
            x = spawnPos.x,
            y = spawnPos.y,
            z = spawnPos.z
        }

        SetModelAsNoLongerNeeded(pedModel)
        if horseModel then
            SetModelAsNoLongerNeeded(horseModel)
        end

        ::continue::
        Wait(75)
    end

    TriggerServerEvent('redm_hunters:serverReportSpawn', data.huntId, data.groupKey, report)
end

local function countAliveHunters()
    local alive = 0
    for _, ped in ipairs(State.hunters) do
        if ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then
            alive = alive + 1
        end
    end
    return alive
end

local function refreshBehaviorLoop()
    CreateThread(function()
        while State.active and State.isController do
            Wait(State.taskRefreshMs)

            local targetPlayer = GetPlayerFromServerId(State.targetServerId)
            if targetPlayer == -1 then
                cdebug('Lost target player reference')
                TriggerServerEvent('redm_hunters:serverControllerFailed', State.huntId, 'target_reference_lost')
                break
            end

            local targetPed = GetPlayerPed(targetPlayer)
            if targetPed == 0 or not DoesEntityExist(targetPed) then
                cdebug('Lost target ped reference')
                TriggerServerEvent('redm_hunters:serverControllerFailed', State.huntId, 'target_ped_lost')
                break
            end

            local targetCoords = GetEntityCoords(targetPed)
            local alive = 0

            for i, hunter in ipairs(State.hunters) do
                if hunter ~= 0 and DoesEntityExist(hunter) and not IsEntityDead(hunter) then
                    alive = alive + 1
                    local hCoords = GetEntityCoords(hunter)
                    local dist = #(hCoords - targetCoords)

                    if State.config.mounted and not State.config.animal then
                        local mounted = IsPedOnMount(hunter)

                        if mounted and dist > State.dismountRange then
                            TaskGoToCoordAnyMeans(hunter, targetCoords.x, targetCoords.y, targetCoords.z, 3.0, 0, false, 0, 0.0)
                        elseif mounted and dist <= State.dismountRange then
                            cdebug(('Hunter idx=%s dismount dist=%.2f group=%s'):format(i, dist, tostring(State.groupKey)))
                            ClearPedTasks(hunter)
                            TaskDismountAnimal(hunter, 0, 0, 0, 0, 0)
                            Wait(250)
                            TaskCombatPed(hunter, targetPed, 0, 16)
                        else
                            TaskCombatPed(hunter, targetPed, 0, 16)
                        end
                    else
                        TaskCombatPed(hunter, targetPed, 0, 16)
                    end
                end
            end

            if alive == 0 then
                cdebug(('All attackers dead on controller huntId=%s group=%s'):format(State.huntId, tostring(State.groupKey)))
                TriggerServerEvent('redm_hunters:serverGroupDead', State.huntId)
                break
            end
        end
    end)
end

local function monitorTargetDeathLoop()
    CreateThread(function()
        while State.active do
            Wait(500)

            if GetPlayerServerId(PlayerId()) == State.targetServerId then
                local me = PlayerPedId()
                if me ~= 0 and DoesEntityExist(me) and IsEntityDead(me) and not State.targetDeadReported then
                    State.targetDeadReported = true
                    cdebug(('Target died locally, reporting huntId=%s'):format(State.huntId))
                    TriggerServerEvent('redm_hunters:serverTargetDied', State.huntId)
                end
            end
        end
    end)
end

RegisterNetEvent('redm_hunters:clientStart', function(data)
    if not data or not data.huntId then
        return
    end

    if State.active then
        cdebug(('Ignoring clientStart; already active huntId=%s'):format(State.huntId))
        return
    end

    resetState()

    State.active = true
    State.huntId = data.huntId
    State.targetServerId = data.target
    State.controllerServerId = data.controller
    State.groupKey = data.groupKey
    State.isController = (GetPlayerServerId(PlayerId()) == data.controller)
    State.config = data.config
    State.dismountRange = data.dismountRange or 24.0
    State.groupSpreadRadius = data.groupSpreadRadius or 10.0
    State.taskRefreshMs = data.taskRefreshMs or 1500

    cdebug(('Hunt start huntId=%s group=%s target=%s controller=%s isController=%s')
        :format(State.huntId, tostring(State.groupKey), tostring(State.targetServerId), tostring(State.controllerServerId), tostring(State.isController)))

    monitorTargetDeathLoop()

    if State.isController then
        spawnGroup(data)
        refreshBehaviorLoop()
    end
end)

RegisterNetEvent('redm_hunters:clientStop', function(huntId, reason)
    if not State.active then
        return
    end

    if huntId ~= State.huntId then
        cdebug(('Ignore stop stale huntId=%s current=%s'):format(tostring(huntId), tostring(State.huntId)))
        return
    end

    cdebug(('Hunt stop huntId=%s reason=%s'):format(huntId, tostring(reason)))
    cleanupEntities()
    resetState()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    cleanupEntities()
    resetState()
end)
