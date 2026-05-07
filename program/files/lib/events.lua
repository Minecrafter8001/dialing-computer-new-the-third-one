-- Stargate event handling and display

local util = require("lib.util")
local feedback = require("lib.feedback")
local stargate = require("lib.stargate")

local lastEventSummary = nil

local EVENT_LOG_FILE = "event_log.json"
local eventLog = {}

local function saveEventLog()
    local serialized = {}
    for index = 1, #eventLog do
        local logEntry = eventLog[index]
        serialized[index] = {
            name = logEntry.name,
            time = logEntry.time,
            args = logEntry.args,
            info = logEntry.info,
        }
    end

    return util.saveJSONFile(EVENT_LOG_FILE, serialized)
end

local function loadEventLog()
    local decoded, errorMessage = util.loadJSONFile(EVENT_LOG_FILE)
    if errorMessage ~= nil then
        return {}, nil
    end

    return decoded, nil
end

local function buildEventInfo(eventName, args)
    if eventName == "stargate_chevron_engaged" then
        local engaged, chevron, isIncoming, symbol = args[1], args[2], args[3], args[4]
        return {
            engaged = engaged,
            chevron = chevron,
            isIncoming = isIncoming,
            symbol = symbol,
            status = (symbol == 0) and "locked" or "encoded",
        }
    elseif eventName == "stargate_incoming_connection" then
        local address, dialType = args[1], args[2]
        return {
            address = type(address) == "table" and util.stringifyAddress(address) or address,
            dialType = dialType,
        }
    elseif eventName == "stargate_incoming_wormhole" then
        return {}
    elseif eventName == "stargate_outgoing_wormhole" then
        local address = args[1]
        return {
            address = type(address) == "table" and util.stringifyAddress(address) or tostring(address),
        }
    elseif eventName == "stargate_disconnected" then
        local feedbackCode = args[1]
        return {
            feedbackCode = feedbackCode,
        }
    elseif eventName == "stargate_reset" then
        local feedbackCode = args[1]
        return {
            feedbackCode = feedbackCode,
        }
    elseif eventName == "stargate_message_received" then
        return {
            message = tostring(args[1]),
        }
    end

    return {}
end

local function buildEventSummary(eventName, args)
    if eventName == "stargate_chevron_engaged" then
        local engaged, chevron, isIncoming, symbol = args[1], args[2], args[3], args[4]
        local status = (symbol == 0) and "Locked" or "Encoded"
        local lastDialedAddress = util.getDialedAddress()
        local totalStr = lastDialedAddress and tostring(#lastDialedAddress) or "?"
        return "Chevron " .. chevron .. " " .. status .. " (" .. engaged .. "/" .. totalStr .. ")"
    elseif eventName == "stargate_incoming_connection" then
        return "Incoming connection detected"
    elseif eventName == "stargate_incoming_wormhole" then
        return "Incoming wormhole formed"
    elseif eventName == "stargate_outgoing_wormhole" then
        local address = args[1]
        if type(address) == "table" then
            return "Wormhole open -> " .. util.stringifyAddress(address)
        end
        return "Outgoing wormhole formed"
    elseif eventName == "stargate_disconnected" then
        return "Disconnected"
    elseif eventName == "stargate_reset" then
        return "Stargate reset"
    elseif eventName == "stargate_message_received" then
        return "Message: " .. tostring(args[1])
    end
    -- format unknown event names: strip "stargate_" prefix, replace underscores with spaces
    return eventName:gsub("^stargate_", ""):gsub("_", " ")
end

local function getLastEventSummary()
    return lastEventSummary
end

local function drawStatusBar()
    local curX, curY = term.getCursorPos()
    local isBlink = term.getCursorBlink()
    term.setCursorBlink(false)

    local interface = stargate.findInterface()
    local gateStatus = interface and stargate.describeInterface(interface) or "Not connected"
    local eventLine = lastEventSummary and ("Last: " .. lastEventSummary) or "No events yet"

    -- Overwrite header lines in-place (lines 3 and 4)
    term.setCursorPos(1, 3)
    term.clearLine()
    term.write("Gate: " .. gateStatus)

    term.setCursorPos(1, 4)
    term.clearLine()
    term.write(eventLine)

    term.setCursorPos(curX, curY)
    term.setCursorBlink(isBlink)
end

local function logEvent(eventName, ...)
    local args = {...}
    table.insert(eventLog, {
        name = eventName,
        time = os.time(),
        args = args,
        info = buildEventInfo(eventName, args),
    })

    if #eventLog > 50 then
        table.remove(eventLog, 1)
    end

    saveEventLog()
end

local function displayEvent(eventName, feedbackMessages, ...)
    local args = {...}
    lastEventSummary = buildEventSummary(eventName, args)
    logEvent(eventName, table.unpack(args))
end

local function listenForEventsWithTimeout(timeoutSeconds, feedbackMessages)
    local startTime = os.clock()
    while os.clock() - startTime < timeoutSeconds do
        local remaining = timeoutSeconds - (os.clock() - startTime)
        if remaining <= 0 then
            break
        end

        local event = {os.pullEventRaw(remaining)}
        local eventName = event[1]

        if eventName:find("^stargate_") then
            displayEvent(eventName, feedbackMessages, table.unpack(event, 3))
        elseif eventName == "key" or eventName == "char" then
            return event
        end
    end

    return nil
end

local function getEventLog()
    return eventLog
end

local function backgroundEventListener(feedbackMessages)
    while true do
        local event = {os.pullEventRaw()}
        local eventName = event[1]

        if eventName:find("^stargate_") then
            displayEvent(eventName, feedbackMessages, table.unpack(event, 3))
            drawStatusBar()
        elseif eventName == "terminate" then
            error("Terminated")
        end
    end
end

return {
    EVENT_LOG_FILE = EVENT_LOG_FILE,
    logEvent = logEvent,
    displayEvent = displayEvent,
    drawStatusBar = drawStatusBar,
    getLastEventSummary = getLastEventSummary,
    listenForEventsWithTimeout = listenForEventsWithTimeout,
    getEventLog = getEventLog,
    saveEventLog = saveEventLog,
    loadEventLog = loadEventLog,
    backgroundEventListener = backgroundEventListener,
}
