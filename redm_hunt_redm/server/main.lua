local Hunt = {
    active = false,
    huntId = 0,
    target = nil,
    controller = nil,
    groupKey = nil
}

local function sdebug(msg)
    if Config.Debug then
        print(('[hunt] %s'):format(msg))
    end
end

local function resetState()
    Hunt.active = false
    Hunt.target = nil
    Hunt.controller = nil
    Hunt.groupKey = nil
end

local function stopHunt(reason)
    if not Hunt.active then
        return
    end

    sdebug(('Stopping hunt: huntId=%s reason=%s target=%s controller=%s group=%s')
        :format(Hunt.huntId, tostring(reason), tostring(Hunt.target), tostring(Hunt.controller), tostring(Hunt.groupKey)))

    TriggerClientEvent('redm_hunters:clientStop', -1, Hunt.huntId, reason or 'stopped')
    resetState()
end

local function startHunt(groupKey, targetId, source)
    if Hunt.active then
        sdebug(('Reject start: active hunt already exists huntId=%s'):format(Hunt.huntId))
        return
    end

    local cfg = Config.Commands[groupKey]
    if not cfg then
        sdebug(('Reject start: invalid groupKey=%s'):format(tostring(groupKey)))
        return
    end

    if not targetId or not GetPlayerName(targetId) then
        sdebug(('Reject start: invalid targetId=%s from source=%s'):format(tostring(targetId), tostring(source)))
        return
    end

    Hunt.huntId = Hunt.huntId + 1
    Hunt.active = true
    Hunt.target = targetId
    Hunt.controller = targetId
    Hunt.groupKey = groupKey

    sdebug(('Starting hunt huntId=%s command=%s target=%s controller=%s targetName=%s')
        :format(Hunt.huntId, groupKey, targetId, Hunt.controller, GetPlayerName(targetId)))

    TriggerClientEvent('redm_hunters:clientStart', -1, {
        huntId = Hunt.huntId,
        target = Hunt.target,
        controller = Hunt.controller,
        groupKey = groupKey,
        config = cfg,
        minSpawnDistance = Config.MinSpawnDistance,
        maxSpawnDistance = Config.MaxSpawnDistance,
        dismountRange = Config.DismountRange,
        groupSpreadRadius = Config.GroupSpreadRadius,
        taskRefreshMs = Config.TaskRefreshMs,
        targetDeadCleanupDelay = Config.TargetDeadCleanupDelay
    })
end

RegisterCommand('sf', function(source, args)
    startHunt('sf', tonumber(args[1]), source)
end, false)

RegisterCommand('nf', function(source, args)
    startHunt('nf', tonumber(args[1]), source)
end, false)

RegisterCommand('is', function(source, args)
    startHunt('is', tonumber(args[1]), source)
end, false)

RegisterCommand('wildlife', function(source, args)
    startHunt('wildlife', tonumber(args[1]), source)
end, false)

RegisterCommand('stophunt', function(source, args)
    stopHunt('manual_stop')
end, false)

RegisterNetEvent('redm_hunters:serverReportSpawn', function(huntId, groupKey, report)
    local src = source

    if not Hunt.active or huntId ~= Hunt.huntId then
        sdebug(('Ignore spawn report: stale huntId=%s current=%s'):format(tostring(huntId), tostring(Hunt.huntId)))
        return
    end

    if src ~= Hunt.controller then
        sdebug(('Ignore spawn report from non-controller=%s controller=%s'):format(src, Hunt.controller))
        return
    end

    sdebug(('Spawn report huntId=%s group=%s controller=%s data=%s')
        :format(huntId, tostring(groupKey), src, json.encode(report)))
end)

RegisterNetEvent('redm_hunters:serverTargetDied', function(huntId)
    local src = source
    if not Hunt.active or huntId ~= Hunt.huntId then
        return
    end

    if src ~= Hunt.target then
        return
    end

    sdebug(('Target died huntId=%s target=%s delaying cleanup=%sms')
        :format(huntId, src, Config.TargetDeadCleanupDelay))

    SetTimeout(Config.TargetDeadCleanupDelay, function()
        stopHunt('target_dead')
    end)
end)

RegisterNetEvent('redm_hunters:serverGroupDead', function(huntId)
    local src = source
    if not Hunt.active or huntId ~= Hunt.huntId then
        return
    end

    if src ~= Hunt.controller then
        return
    end

    sdebug(('All attackers dead huntId=%s group=%s'):format(huntId, tostring(Hunt.groupKey)))
    stopHunt('group_dead')
end)

RegisterNetEvent('redm_hunters:serverControllerFailed', function(huntId, reason)
    local src = source
    if not Hunt.active or huntId ~= Hunt.huntId then
        return
    end

    if src ~= Hunt.controller then
        return
    end

    sdebug(('Controller failure huntId=%s reason=%s'):format(huntId, tostring(reason)))
    stopHunt(reason or 'controller_failed')
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    if not Hunt.active then
        return
    end

    if src == Hunt.target then
        sdebug(('Target disconnected huntId=%s target=%s reason=%s'):format(Hunt.huntId, src, tostring(reason)))
        stopHunt('target_disconnected')
        return
    end

    if src == Hunt.controller then
        sdebug(('Controller disconnected huntId=%s controller=%s reason=%s'):format(Hunt.huntId, src, tostring(reason)))
        stopHunt('controller_disconnected')
    end
end)
