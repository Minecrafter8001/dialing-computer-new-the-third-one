-- Stargate interface operations

local feedback = require("lib.feedback")
local util = require("lib.util")

local ROTATION_DIRECTION_DELAY = 0.25
local CHEVRON_ACTION_DELAY = 0.3

local lastRotationDirection = nil

local function findInterface()
    return peripheral.find("basic_interface")
end

local function describeInterface(interface)
    if interface.isStargateConnected ~= nil and interface.isWormholeOpen ~= nil then
        local connected = interface.isStargateConnected()
        local open = interface.isWormholeOpen()

        if open then
            return "Connected, wormhole open"
        end

        if connected then
            return "Connected, wormhole forming"
        end

        return "Idle"
    end

    return "Status unknown"
end

local function isFailureFeedback(feedbackCode)
    return type(feedbackCode) == "number" and feedbackCode < 0
end

local function isIgnoredClearFeedback(feedbackCode)
    return feedbackCode == -6 or feedbackCode == -5
end

local function waitForCurrentSymbol(interface, symbol)
    while not interface.isCurrentSymbol(symbol) do
        sleep(0)
    end
end

local function getRotationDirection(interface, symbol)

    local currentSymbol = interface.getCurrentSymbol()
    if type(currentSymbol) ~= "number" or currentSymbol < 0 then
        return interface.rotateClockwise, "clockwise"
    end

    local clockwiseDistance = (symbol - currentSymbol) % 39
    local antiClockwiseDistance = (currentSymbol - symbol) % 39

    if antiClockwiseDistance < clockwiseDistance then
        return interface.rotateAntiClockwise, "anticlockwise"
    end

    return interface.rotateClockwise, "clockwise"
end

local function rotateToSymbol(interface, symbol, feedbackMessages)
    local rotate, direction = getRotationDirection(interface, symbol)

    if lastRotationDirection ~= nil and lastRotationDirection ~= direction then
        sleep(ROTATION_DIRECTION_DELAY)
    end

    local feedbackCode = rotate(symbol)
    lastRotationDirection = direction

    return feedbackCode
end

local function EngageChevron(interface, feedbackMessages)
    local gateType = interface.getStargateType()

    if gateType == "sgjourney:milky_way_stargate" then
        local openFeedback = interface.openChevron()
        if isFailureFeedback(openFeedback) then
            return false, "Failed to open chevron while engaging with feedback " .. feedback.formatFeedback(feedbackMessages, openFeedback), openFeedback
        end
        sleep(CHEVRON_ACTION_DELAY)

        local closeFeedback = interface.closeChevron()
        if isFailureFeedback(closeFeedback) then
            return false, "Failed to close chevron while engaging with feedback " .. feedback.formatFeedback(feedbackMessages, closeFeedback), closeFeedback
        end
        sleep(CHEVRON_ACTION_DELAY)

        return true, nil, closeFeedback
    else
        if interface.encodeChevron == nil then
            return false, "encodeChevron is not available on this interface", nil
        end

        local feedbackCode = interface.encodeChevron()
        if isFailureFeedback(feedbackCode) then
            return false, "encodeChevron failed with feedback " .. feedback.formatFeedback(feedbackMessages, feedbackCode), feedbackCode
        end
        sleep(CHEVRON_ACTION_DELAY)

        return true, nil, feedbackCode
    end
end

local function clearEngagedChevrons(interface, feedbackMessages)
    if interface.getChevronsEngaged == nil then
        return true, nil
    end

    local engagedChevrons = interface.getChevronsEngaged()
    if type(engagedChevrons) ~= "number" or engagedChevrons <= 0 then
        return true, nil
    end

    local feedbackCode = rotateToSymbol(interface, 0, feedbackMessages)
    if isFailureFeedback(feedbackCode) then
        return false, "Failed to rotate to point of origin while clearing with feedback " .. feedback.formatFeedback(feedbackMessages, feedbackCode)
    end

    waitForCurrentSymbol(interface, 0)

    local ok, engageMessage, engageFeedback = EngageChevron(interface, feedbackMessages)
    if not ok then
        if isIgnoredClearFeedback(engageFeedback) then
            return true, engageFeedback
        end

        return false, engageMessage
    end

    if isIgnoredClearFeedback(engageFeedback) then
        return true, engageFeedback
    end

    return true, engageFeedback
end

local function dialAddress(interface, address, feedbackMessages)
    local lastFeedback = feedback.FEEDBACK_OK
    lastRotationDirection = nil

    util.setDialedAddress(address)

    if interface.disconnectStargate ~= nil and interface.isStargateConnected ~= nil and interface.isStargateConnected() then
        interface.disconnectStargate()
        sleep(0.5)
    end

    local cleared, clearResult = clearEngagedChevrons(interface, feedbackMessages)
    if not cleared then
        return false, clearResult
    end

    if type(clearResult) == "number" then
        lastFeedback = clearResult
    end

    for index = 1, #address do
        local symbol = address[index]
        local feedbackCode = rotateToSymbol(interface, symbol, feedbackMessages)

        if isFailureFeedback(feedbackCode) then
            return false, "Rotation failed on symbol " .. tostring(symbol) .. " with feedback " .. feedback.formatFeedback(feedbackMessages, feedbackCode)
        end

        if type(feedbackCode) == "number" then
            lastFeedback = feedbackCode
        end

        waitForCurrentSymbol(interface, symbol)

        local ok, engageMessage, engageFeedback = EngageChevron(interface, feedbackMessages)
        if not ok then
            return false, engageMessage
        end

        if type(engageFeedback) == "number" then
            lastFeedback = engageFeedback
        end

        sleep(0.2)
    end

    return true, lastFeedback
end

return {
    ROTATION_DIRECTION_DELAY = ROTATION_DIRECTION_DELAY,
    CHEVRON_ACTION_DELAY = CHEVRON_ACTION_DELAY,
    findInterface = findInterface,
    describeInterface = describeInterface,
    isFailureFeedback = isFailureFeedback,
    isIgnoredClearFeedback = isIgnoredClearFeedback,
    waitForCurrentSymbol = waitForCurrentSymbol,
    getRotationDirection = getRotationDirection,
    rotateToSymbol = rotateToSymbol,
    clearEngagedChevrons = clearEngagedChevrons,
    dialAddress = dialAddress,
}
