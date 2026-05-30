-- DeployActionProbe — dev-only tool to discover deploy menu actionId values (hero slots).
-- See docs/spec-deploy-action-probe.md

local SetTimeout = require("common/timer").SetTimeout

-- <Settings>
local PROBE_KNOWN_RANGE_MIN <const> = 871087115
local PROBE_KNOWN_RANGE_MAX <const> = 871087135
local PROBE_DELAY_SEC <const> = 1.5
local PROBE_MAX_RANGE_SPAN <const> = 50
local PROBE_ADMINS <const> = { "TonPseudo" }
-- </Settings>

local LOG_PREFIX <const> = "[DeployActionProbe] "

local function split(str, sep)
    local t = {}
    for part in string.gmatch(str, "([^" .. (sep or "%s") .. "]+)") do
        table.insert(t, part)
    end
    return t
end

local function logLine(kind, playerName, actionId, enabled)
    local enabledStr = enabled and "true" or "false"
    local line = string.format(
        "%s%s player=%s actionId=%s enabled=%s",
        LOG_PREFIX,
        kind,
        playerName or "?",
        tostring(actionId),
        enabledStr
    )
    print(line)
end

local ProbeService = {
    states = {},
}

function ProbeService:isAdmin(playerName)
    if playerName == nil then
        return false
    end
    local lower = playerName:lower()
    for _, admin in ipairs(PROBE_ADMINS) do
        if admin:lower() == lower then
            return true
        end
    end
    return false
end

function ProbeService:getState(player)
    local key = player.playerId
    if self.states[key] == nil then
        self.states[key] = {
            lastSingleId = nil,
            rangeMin = nil,
            rangeMax = nil,
            autoEnabled = false,
        }
    end
    return self.states[key]
end

function ProbeService:clearState(player)
    self.states[player.playerId] = nil
end

function ProbeService:findHumanByName(name)
    if name == nil or name == "" then
        return nil
    end
    local exact = PlayerManager.GetPlayer(name)
    if exact ~= nil and not exact.isBot then
        return exact
    end
    for _, p in ipairs(PlayerManager.GetPlayers()) do
        if not p.isBot and p.name:lower() == name:lower() then
            return p
        end
    end
    return nil
end

function ProbeService:notify(message)
    Console.Execute("Kyber.Broadcast " .. LOG_PREFIX .. message)
end

function ProbeService:reactivateAll(player, state)
    for id = PROBE_KNOWN_RANGE_MIN, PROBE_KNOWN_RANGE_MAX do
        player:SetInputEnabled(id, true)
    end
    if state.rangeMin ~= nil and state.rangeMax ~= nil then
        for id = state.rangeMin, state.rangeMax do
            player:SetInputEnabled(id, true)
        end
    end
    if state.lastSingleId ~= nil then
        player:SetInputEnabled(state.lastSingleId, true)
    end
    logLine("off", player.name, "all-known", true)
end

function ProbeService:applySingle(target, actionId)
    local state = self:getState(target)
    if state.lastSingleId ~= nil and state.lastSingleId ~= actionId then
        target:SetInputEnabled(state.lastSingleId, true)
        logLine("single-clear", target.name, state.lastSingleId, true)
    end
    target:SetInputEnabled(actionId, false)
    state.lastSingleId = actionId
    logLine("single", target.name, actionId, false)
    self:notify(string.format(
        "Probe: disabled %d on %s — test hero / classes / vehicle, then /probe off",
        actionId,
        target.name
    ))
end

function ProbeService:applyRange(target, rangeMin, rangeMax)
    if rangeMax < rangeMin then
        self:notify("Invalid range: end must be >= start")
        return false
    end
    if rangeMax - rangeMin > PROBE_MAX_RANGE_SPAN then
        self:notify(string.format(
            "Range too large (max %d IDs). Narrow debut/fin.",
            PROBE_MAX_RANGE_SPAN
        ))
        return false
    end
    local state = self:getState(target)
    for id = rangeMin, rangeMax do
        target:SetInputEnabled(id, false)
    end
    state.rangeMin = rangeMin
    state.rangeMax = rangeMax
    logLine("range", target.name, string.format("%d-%d", rangeMin, rangeMax), false)
    self:notify(string.format(
        "Probe: disabled %d..%d on %s — note what is blocked; use /probe enableone <id> or /probe off",
        rangeMin,
        rangeMax,
        target.name
    ))
    return true
end

function ProbeService:applyEnableOne(target, actionId)
    target:SetInputEnabled(actionId, true)
    logLine("enableone", target.name, actionId, true)
    self:notify(string.format(
        "Probe: re-enabled %d on %s — check if hero slot is selectable",
        actionId,
        target.name
    ))
end

function ProbeService:resolveTarget(sender, optionalName, needsAdminForOther)
    if sender == nil or sender.isBot then
        return nil, "Invalid sender"
    end
    if optionalName == nil or optionalName == "" then
        return sender, nil
    end
    if optionalName:lower() == sender.name:lower() then
        return sender, nil
    end
    if needsAdminForOther and not self:isAdmin(sender.name) then
        return nil, "Only admins can target another player (edit PROBE_ADMINS)"
    end
    local target = self:findHumanByName(optionalName)
    if target == nil then
        return nil, "Player not found: " .. optionalName
    end
    return target, nil
end

function ProbeService:parseActionId(str)
    local id = tonumber(str)
    if id == nil then
        return nil
    end
    return math.floor(id)
end

function ProbeService:cmdHelp()
    self:notify("Commands: help | single <id> [name] | range <min> <max> [name] | enableone <id> [name] | auto on|off | off [name|all] | status")
end

function ProbeService:cmdStatus(sender)
    local state = self:getState(sender)
    local rangeStr = "none"
    if state.rangeMin ~= nil then
        rangeStr = string.format("%d..%d", state.rangeMin, state.rangeMax)
    end
    local singleStr = state.lastSingleId ~= nil and tostring(state.lastSingleId) or "none"
    local autoStr = state.autoEnabled and "on" or "off"
    self:notify(string.format(
        "Status %s: single=%s range=%s auto=%s",
        sender.name,
        singleStr,
        rangeStr,
        autoStr
    ))
end

function ProbeService:cmdOff(sender, arg)
    if arg ~= nil and arg:lower() == "all" then
        if not self:isAdmin(sender.name) then
            self:notify("Only admins can use /probe off all")
            return
        end
        for _, p in ipairs(PlayerManager.GetPlayers()) do
            if not p.isBot then
                local state = self:getState(p)
                self:reactivateAll(p, state)
                self:clearState(p)
            end
        end
        self:notify("Probe: re-enabled all known IDs for every human player")
        return
    end

    local target, err = self:resolveTarget(sender, arg, true)
    if err ~= nil then
        self:notify(err)
        return
    end
    if target == nil then
        return
    end
    local state = self:getState(target)
    self:reactivateAll(target, state)
    state.lastSingleId = nil
    state.rangeMin = nil
    state.rangeMax = nil
    self:notify("Probe: all known IDs re-enabled for " .. target.name)
end

function ProbeService:handleCommand(sender, parts)
    if #parts < 2 then
        self:cmdHelp()
        return
    end

    local sub = parts[2]:lower()

    if sub == "help" or sub == "?" then
        self:cmdHelp()
        return
    end

    if sub == "status" then
        self:cmdStatus(sender)
        return
    end

    if sub == "off" then
        self:cmdOff(sender, parts[3])
        return
    end

    if sub == "auto" then
        if #parts < 3 then
            self:notify("Usage: /probe auto on | off")
            return
        end
        local mode = parts[3]:lower()
        local state = self:getState(sender)
        if mode == "on" then
            state.autoEnabled = true
            self:notify("Probe auto: on — after death, last single ID is re-applied in " .. PROBE_DELAY_SEC .. "s")
        elseif mode == "off" then
            state.autoEnabled = false
            self:notify("Probe auto: off")
        else
            self:notify("Usage: /probe auto on | off")
        end
        return
    end

    if sub == "single" then
        if #parts < 3 then
            self:notify("Usage: /probe single <actionId> [player]")
            return
        end
        local actionId = self:parseActionId(parts[3])
        if actionId == nil then
            self:notify("Invalid actionId")
            return
        end
        local target, err = self:resolveTarget(sender, parts[4], true)
        if err ~= nil then
            self:notify(err)
            return
        end
        self:applySingle(target, actionId)
        return
    end

    if sub == "range" then
        if #parts < 4 then
            self:notify("Usage: /probe range <debut> <fin> [player]")
            return
        end
        local rangeMin = self:parseActionId(parts[3])
        local rangeMax = self:parseActionId(parts[4])
        if rangeMin == nil or rangeMax == nil then
            self:notify("Invalid range bounds")
            return
        end
        local target, err = self:resolveTarget(sender, parts[5], true)
        if err ~= nil then
            self:notify(err)
            return
        end
        self:applyRange(target, rangeMin, rangeMax)
        return
    end

    if sub == "enableone" then
        if #parts < 3 then
            self:notify("Usage: /probe enableone <actionId> [player]")
            return
        end
        local actionId = self:parseActionId(parts[3])
        if actionId == nil then
            self:notify("Invalid actionId")
            return
        end
        local target, err = self:resolveTarget(sender, parts[4], true)
        if err ~= nil then
            self:notify(err)
            return
        end
        self:applyEnableOne(target, actionId)
        return
    end

    self:cmdHelp()
end

EventManager.Listen("ServerPlayer:SendMessage", function(sender, message)
    if sender == nil or sender.isBot then
        return
    end
    if message == nil or #message < 6 then
        return
    end

    local parts = split(message)
    if #parts < 1 then
        return
    end

    local head = parts[1]:lower()
    if head ~= "/probe" and head ~= "!probe" then
        return
    end

    EventManager.SetCancelled(true)
    ProbeService:handleCommand(sender, parts)
end)

EventManager.Listen("ServerPlayer:Killed", function(victim, _killer)
    if victim == nil or victim.isBot then
        return
    end

    local state = ProbeService:getState(victim)
    if not state.autoEnabled or state.lastSingleId == nil then
        return
    end

    local victimName = victim.name
    local actionId = state.lastSingleId

    SetTimeout(function()
        local player = ProbeService:findHumanByName(victimName)
        if player == nil then
            return
        end
        local st = ProbeService:getState(player)
        if not st.autoEnabled or st.lastSingleId ~= actionId then
            return
        end
        player:SetInputEnabled(actionId, false)
        logLine("auto", player.name, actionId, false)
        ProbeService:notify(string.format(
            "Probe auto: re-disabled %d on %s — test deploy screen",
            actionId,
            player.name
        ))
    end, PROBE_DELAY_SEC)
end)

EventManager.Listen("ServerPlayer:Spawned", function(player)
    if player == nil or player.isBot then
        return
    end
    local state = ProbeService.states[player.playerId]
    if state == nil then
        return
    end
    ProbeService:reactivateAll(player, state)
end)

EventManager.Listen("ServerPlayer:Disconnect", function(player)
    if player == nil or player.isBot then
        return
    end
    local state = ProbeService.states[player.playerId]
    if state == nil then
        return
    end
    ProbeService:reactivateAll(player, state)
    ProbeService:clearState(player)
end)

print(LOG_PREFIX .. "loaded (dev only — set PROBE_ADMINS and use /probe help)")
