local activeEncounter = nil

local function log(msg)
    print(('%s [SERVER] %s'):format(Config.DebugPrefix, msg))
end

local function resetEncounter(reason)
    if activeEncounter then
        log(('reset encounter id=%s reason=%s'):format(activeEncounter.id, reason or 'none'))
        if activeEncounter.timeoutTimer then
            activeEncounter.timeoutTimer = nil
        end
        activeEncounter = nil
    end
end

local function getPlayerCoords(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    return vector3(coords.x, coords.y, coords.z)
end

local function chooseController(targetSrc)
    local targetCoords = getPlayerCoords(targetSrc)
    if not targetCoords then
        return targetSrc
    end

    local bestSrc = targetSrc
    local bestDist = math.huge

    for _, s in ipairs(GetPlayers()) do
        local id = tonumber(s)
        local coords = getPlayerCoords(id)
        if coords then
            local dist = #(coords - targetCoords)
            if dist < bestDist and dist <= Config.ControllerSelectRadius then
                bestSrc = id
                bestDist = dist
            end
        end
    end

    return bestSrc
end

local function beginEncounter(requester, command, groupType, targetSrc)
    if activeEncounter then
        log(('reject new encounter requester=%s, existing=%s'):format(requester, activeEncounter.id))
        return
    end

    local controller = chooseController(targetSrc)
    local targetCoords = getPlayerCoords(targetSrc)
    if not targetCoords then
        log(('failed to start command=/%s target=%s reason=target_coords_nil'):format(command, targetSrc))
        return
    end

    local encounterId = ('%d_%d_%d'):format(os.time(), targetSrc, math.random(1000, 9999))

    activeEncounter = {
        id = encounterId,
        requester = requester,
        command = command,
        groupType = groupType,
        targetSrc = targetSrc,
        controller = controller,
        startedAt = GetGameTimer(),
        state = 'spawning'
    }

    log(('start id=%s command=/%s requester=%s target=%s controller=%s group=%s targetCoords=(%.2f, %.2f, %.2f)')
        :format(encounterId, command, requester, targetSrc, controller, groupType, targetCoords.x, targetCoords.y, targetCoords.z))

    TriggerClientEvent('hunter:client:startEncounter', controller, {
        encounterId = encounterId,
        groupType = groupType,
        targetServerId = targetSrc,
        command = command,
        targetCoords = { x = targetCoords.x, y = targetCoords.y, z = targetCoords.z }
    })

    SetTimeout(Config.EncounterTimeoutMs, function()
        if activeEncounter and activeEncounter.id == encounterId then
            log(('timeout id=%s forcing stop'):format(encounterId))
            TriggerClientEvent('hunter:client:stopEncounter', controller, encounterId, 'timeout')
            resetEncounter('timeout')
        end
    end)
end

local function onCommand(source, command, args)
    local targetArg = args[1]
    local targetSrc = tonumber(targetArg)
    local groupType = Config.Commands[command]

    if not groupType then
        return
    end

    if not targetSrc or not GetPlayerName(targetSrc) then
        log(('invalid target command=/%s requester=%s arg=%s'):format(command, source, tostring(targetArg)))
        return
    end

    beginEncounter(source, command, groupType, targetSrc)
end

for commandName, _ in pairs(Config.Commands) do
    RegisterCommand(commandName, function(source, args)
        if source == 0 then
            log(('ignored console command /%s'):format(commandName))
            return
        end
        onCommand(source, commandName, args)
    end, false)
end

RegisterNetEvent('hunter:server:controllerSpawned', function(encounterId, payload)
    local src = source
    if not activeEncounter or activeEncounter.id ~= encounterId or src ~= activeEncounter.controller then
        return
    end

    activeEncounter.state = 'active'

    log(('spawned id=%s group=%s controller=%s target=%s spawn=(%.2f, %.2f, %.2f) distance=%.2f entities=%s')
        :format(encounterId, activeEncounter.groupType, src, activeEncounter.targetSrc,
            payload.spawn.x, payload.spawn.y, payload.spawn.z, payload.distance,
            json.encode(payload.entities)))

    TriggerClientEvent('hunter:client:observeEncounter', -1, encounterId, payload.entities)
end)

RegisterNetEvent('hunter:server:controllerState', function(encounterId, state)
    local src = source
    if not activeEncounter or activeEncounter.id ~= encounterId or src ~= activeEncounter.controller then
        return
    end

    if state == 'target_dead' or state == 'target_missing' or state == 'group_dead' then
        log(('state id=%s state=%s -> stop+cleanup'):format(encounterId, state))
        TriggerClientEvent('hunter:client:stopEncounter', src, encounterId, state)
        resetEncounter(state)
        return
    end

    if state == 'manual_stop' then
        log(('manual stop id=%s by controller=%s'):format(encounterId, src))
        TriggerClientEvent('hunter:client:stopEncounter', src, encounterId, state)
        resetEncounter(state)
    end
end)

RegisterNetEvent('hunter:server:controllerCleanupDone', function(encounterId, report)
    local src = source
    log(('cleanup complete id=%s controller=%s report=%s'):format(encounterId, src, json.encode(report)))
end)

AddEventHandler('playerDropped', function()
    local src = source
    if not activeEncounter then return end

    if src == activeEncounter.targetSrc then
        log(('target disconnected id=%s target=%s'):format(activeEncounter.id, src))
        TriggerClientEvent('hunter:client:stopEncounter', activeEncounter.controller, activeEncounter.id, 'target_disconnect')
        resetEncounter('target_disconnect')
        return
    end

    if src == activeEncounter.controller then
        log(('controller disconnected id=%s -> stopping encounter for safety'):format(activeEncounter.id))
        resetEncounter('controller_disconnect')
    end
end)

RegisterCommand('stophunt', function(source)
    if source == 0 then return end
    if not activeEncounter then return end

    local allowed = source == activeEncounter.requester or source == activeEncounter.targetSrc or source == activeEncounter.controller
    if not allowed then return end

    log(('stophunt requester=%s id=%s'):format(source, activeEncounter.id))
    TriggerClientEvent('hunter:client:stopEncounter', activeEncounter.controller, activeEncounter.id, 'manual_stop')
    resetEncounter('manual_stop')
end, false)
