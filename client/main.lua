local encounter = nil

local function log(msg)
    print(('%s [CLIENT %s] %s'):format(Config.DebugPrefix, GetPlayerServerId(PlayerId()), msg))
end

local function requestModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) do
        Wait(0)
        if GetGameTimer() > timeout then
            return nil
        end
    end
    return hash
end

local function randomAround(base, radiusMin, radiusMax)
    local angle = math.rad(math.random(0, 360))
    local radius = math.random() * (radiusMax - radiusMin) + radiusMin
    local x = base.x + math.cos(angle) * radius
    local y = base.y + math.sin(angle) * radius
    return x, y, base.z + 50.0
end

local function findGroundNearTarget(targetCoords)
    for _ = 1, Config.SpawnTryCount do
        local x, y, z = randomAround(targetCoords, Config.SpawnDistanceMin, Config.SpawnDistanceMax)
        local found, gz = GetGroundZFor_3dCoord(x, y, z, true)
        if found then
            local clear = IsPointOnRoad(x, y, gz, 0)
            if clear then
                return vector3(x, y, gz)
            end
        end
    end
    return vector3(targetCoords.x + Config.SpawnDistanceMin, targetCoords.y, targetCoords.z)
end

local function ensureEntityNetworked(entity)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    SetNetworkIdExistsOnAllMachines(netId, true)
    SetNetworkIdCanMigrate(netId, true)
    return netId
end


local function mountRider(rider, horse)
    if type(SetPedOnMount) == 'function' then
        SetPedOnMount(rider, horse, -1, true)
        return true
    end

    if type(TaskMountAnimal) == 'function' then
        TaskMountAnimal(rider, horse, -1, -1, 2.0, 1, 0, 0)
        return true
    end

    return false
end

local function assignCombatPed(ped, targetPed, weaponHash, meleeOnly)
    SetPedAsEnemy(ped, true)
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAttributes(ped, 5, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedAccuracy(ped, meleeOnly and 25 or 50)
    SetPedSeeingRange(ped, 200.0)
    SetPedHearingRange(ped, 200.0)
    SetPedDropsWeaponsWhenDead(ped, false)

    if weaponHash and weaponHash ~= 0 then
        GiveWeaponToPed_2(ped, weaponHash, 80, true, 0, false, 0.5, 1.0, 752097756, false, 0, false)
    end

    TaskCombatPed(ped, targetPed, 0, 16)
end

local function spawnPed(model, coords, heading)
    local hash = requestModel(model)
    if not hash then return nil, nil, nil end
    local ped = CreatePed(hash, coords.x, coords.y, coords.z, heading or 0.0, true, true, true, true)
    if ped == 0 then return nil, nil, hash end
    SetEntityAsMissionEntity(ped, true, true)
    local netId = ensureEntityNetworked(ped)
    return ped, netId, hash
end

local function spawnHorseWithRider(groupCfg, spawnPos, i)
    local horseModel = groupCfg.horseModels[(i - 1) % #groupCfg.horseModels + 1]
    local riderModel = groupCfg.pedModels[(i - 1) % #groupCfg.pedModels + 1]

    local offset = vector3(spawnPos.x + (i * 2.5), spawnPos.y + (i % 2 == 0 and 4.0 or -4.0), spawnPos.z)

    local horse, horseNet, horseHash = spawnPed(horseModel, offset, math.random(0, 360) + 0.0)
    if not horse then return nil end

    local rider, riderNet, riderHash = spawnPed(riderModel, offset, GetEntityHeading(horse))
    if not rider then
        DeleteEntity(horse)
        return nil
    end

    local mounted = mountRider(rider, horse)
    if not mounted then
        log(('mount fallback failed rider=%s horse=%s, using foot behavior'):format(rider, horse))
    end

    return {
        rider = rider,
        riderNet = riderNet,
        riderHash = riderHash,
        horse = horse,
        horseNet = horseNet,
        horseHash = horseHash
    }
end

local function spawnFootPed(groupCfg, spawnPos, i)
    local model = groupCfg.pedModels[(i - 1) % #groupCfg.pedModels + 1]
    local offset = vector3(spawnPos.x + math.random(-6, 6), spawnPos.y + math.random(-6, 6), spawnPos.z)
    local ped, netId, hash = spawnPed(model, offset, math.random(0, 360) + 0.0)
    if not ped then return nil end
    return { rider = ped, riderNet = netId, riderHash = hash }
end

local function cleanupEncounter(reason)
    if not encounter then return end

    Wait(Config.CleanupDelayMs)

    local deletedPeds = 0
    local deletedHorses = 0

    for _, member in ipairs(encounter.members) do
        if member.rider and DoesEntityExist(member.rider) then
            DeleteEntity(member.rider)
            deletedPeds = deletedPeds + 1
        end
        if member.horse and DoesEntityExist(member.horse) then
            DeleteEntity(member.horse)
            deletedHorses = deletedHorses + 1
        end
    end

    log(('cleanup id=%s reason=%s deletedPeds=%d deletedHorses=%d'):format(encounter.id, reason, deletedPeds, deletedHorses))
    TriggerServerEvent('hunter:server:controllerCleanupDone', encounter.id, {
        reason = reason,
        deletedPeds = deletedPeds,
        deletedHorses = deletedHorses
    })

    encounter = nil
end

local function driveMountedGroup(targetPed)
    CreateThread(function()
        while encounter and encounter.running do
            local targetCoords = GetEntityCoords(targetPed)
            for _, member in ipairs(encounter.members) do
                if member.rider and DoesEntityExist(member.rider) and not IsEntityDead(member.rider) then
                    local dist = #(GetEntityCoords(member.rider) - targetCoords)
                    if member.horse and DoesEntityExist(member.horse) and not member.dismounted then
                        if dist > encounter.groupCfg.dismountDistance then
                            TaskGoToEntity(member.rider, targetPed, -1, 15.0, 4.0, 0.0, 0)
                        else
                            ClearPedTasks(member.rider)
                            TaskDismountAnimal(member.rider, 0, 0, 0, 0, 0)
                            member.dismounted = true
                            member.dismountAt = GetGameTimer()
                        end
                    else
                        assignCombatPed(member.rider, targetPed, member.weaponHash, false)
                    end
                end
            end
            Wait(1000)
        end
    end)
end

local function driveFootGroup(targetPed, meleeOnly)
    CreateThread(function()
        while encounter and encounter.running do
            for _, member in ipairs(encounter.members) do
                if member.rider and DoesEntityExist(member.rider) and not IsEntityDead(member.rider) then
                    assignCombatPed(member.rider, targetPed, member.weaponHash, meleeOnly)
                end
            end
            Wait(1100)
        end
    end)
end

local function startMonitor(targetServerId)
    CreateThread(function()
        while encounter and encounter.running do
            local targetPlayer = GetPlayerFromServerId(targetServerId)
            if targetPlayer == -1 then
                TriggerServerEvent('hunter:server:controllerState', encounter.id, 'target_missing')
                return
            end

            local targetPed = GetPlayerPed(targetPlayer)
            if targetPed == 0 or IsEntityDead(targetPed) then
                TriggerServerEvent('hunter:server:controllerState', encounter.id, 'target_dead')
                return
            end

            local aliveCount = 0
            for _, member in ipairs(encounter.members) do
                if member.rider and DoesEntityExist(member.rider) and not IsEntityDead(member.rider) then
                    aliveCount = aliveCount + 1
                end
            end

            if aliveCount == 0 then
                TriggerServerEvent('hunter:server:controllerState', encounter.id, 'group_dead')
                return
            end

            Wait(1000)
        end
    end)
end

local function spawnEncounter(data)
    local groupCfg = Config.Groups[data.groupType]
    if not groupCfg then
        log(('unknown group type %s'):format(tostring(data.groupType)))
        return
    end

    local targetPlayer = GetPlayerFromServerId(data.targetServerId)
    if targetPlayer == -1 then
        log(('spawn failed id=%s target not streamed'):format(data.encounterId))
        return
    end

    local targetPed = GetPlayerPed(targetPlayer)
    if targetPed == 0 then
        log(('spawn failed id=%s target ped nil'):format(data.encounterId))
        return
    end

    local targetCoords = GetEntityCoords(targetPed)
    local spawnPos = findGroundNearTarget(targetCoords)

    encounter = {
        id = data.encounterId,
        groupType = data.groupType,
        groupCfg = groupCfg,
        targetServerId = data.targetServerId,
        members = {},
        running = true
    }

    local entityReport = {}

    for i = 1, groupCfg.count do
        local member = groupCfg.mounted and spawnHorseWithRider(groupCfg, spawnPos, i) or spawnFootPed(groupCfg, spawnPos, i)
        if member then
            member.weaponHash = groupCfg.weapons[((i - 1) % math.max(#groupCfg.weapons, 1)) + 1] or 0
            table.insert(encounter.members, member)

            table.insert(entityReport, {
                riderNet = member.riderNet,
                riderHash = member.riderHash,
                horseNet = member.horseNet,
                horseHash = member.horseHash,
                weapon = member.weaponHash
            })
        end
    end

    local spawnDist = #(spawnPos - targetCoords)
    log(('spawn id=%s type=%s target=%s spawn=(%.2f %.2f %.2f) distance=%.2f members=%d')
        :format(encounter.id, encounter.groupType, encounter.targetServerId, spawnPos.x, spawnPos.y, spawnPos.z, spawnDist, #encounter.members))

    TriggerServerEvent('hunter:server:controllerSpawned', encounter.id, {
        spawn = { x = spawnPos.x, y = spawnPos.y, z = spawnPos.z },
        distance = spawnDist,
        entities = entityReport
    })

    if data.groupType == 'wildlife' then
        driveFootGroup(targetPed, true)
    elseif data.groupType == 'nightfolk' then
        driveFootGroup(targetPed, true)
    elseif data.groupType == 'sheriff' or data.groupType == 'indigenous' then
        driveMountedGroup(targetPed)
    else
        driveFootGroup(targetPed, false)
    end

    startMonitor(data.targetServerId)
end

RegisterNetEvent('hunter:client:startEncounter', function(data)
    if encounter and encounter.running then
        log(('refuse start, already running id=%s'):format(encounter.id))
        return
    end
    spawnEncounter(data)
end)

RegisterNetEvent('hunter:client:takeoverEncounter', function(data)
    if encounter and encounter.running then
        log(('takeover blocked id=%s because local encounter=%s still running'):format(data.encounterId, encounter.id))
        return
    end

    log(('takeover requested id=%s type=%s target=%s'):format(data.encounterId, data.groupType, data.targetServerId))
    spawnEncounter(data)
end)

RegisterNetEvent('hunter:client:observeEncounter', function(encounterId, entities)
    log(('observe id=%s entities=%s'):format(encounterId, json.encode(entities)))
end)

RegisterNetEvent('hunter:client:stopEncounter', function(encounterId, reason)
    if not encounter or encounter.id ~= encounterId then
        return
    end

    encounter.running = false
    log(('stop id=%s reason=%s'):format(encounterId, reason))
    cleanupEncounter(reason)
end)

RegisterCommand('stophunt', function()
    if encounter and encounter.running then
        TriggerServerEvent('hunter:server:controllerState', encounter.id, 'manual_stop')
    end
end, false)
