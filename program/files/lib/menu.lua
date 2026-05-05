-- Menu handlers for address book operations

local util = require("lib.util")
local feedback = require("lib.feedback")
local address = require("lib.address")
local ui = require("lib.ui")
local stargate = require("lib.stargate")

local function reloadAddressBook(addressBook)
    local fresh, err = address.loadAddressBook()
    if fresh == nil then return end
    -- replace in-place so all callers see the update
    for k in pairs(addressBook) do addressBook[k] = nil end
    for i, v in ipairs(fresh) do addressBook[i] = v end
end

local function addEntry(addressBook, feedbackMessages)
    ui.clearScreen()
    print("Add Address")
    print(string.rep("-", 11))

    local name = ui.prompt("Name: ", feedbackMessages)
    if name == "" then
        printError("Name is required.")
        ui.pause()
        return
    end

    local rawAddress = ui.prompt("Address symbols: ", feedbackMessages)
    local parsedAddress, errorMessage = address.normalizeAddress(rawAddress)
    if parsedAddress == nil then
        printError(errorMessage)
        ui.pause()
        return
    end

    local ok, saveError = address.addEntry(name, parsedAddress)
    if not ok then
        printError(saveError)
        ui.pause()
        return
    end

    reloadAddressBook(addressBook)
    print("Saved " .. name .. ".")
    ui.pause()
end

local function removeEntry(addressBook, feedbackMessages)
    ui.clearScreen()
    print("Remove Address")
    print(string.rep("-", 14))

    local index, errorMessage = ui.chooseEntry(addressBook, feedbackMessages)
    if index == nil then
        printError(errorMessage)
        ui.pause()
        return
    end

    local entry = addressBook[index]
    local ok, saveError = address.removeEntry(entry.name)
    if not ok then
        printError(saveError)
        ui.pause()
        return
    end

    reloadAddressBook(addressBook)
    print("Removed " .. entry.name .. ".")
    ui.pause()
end

local function renameEntry(addressBook, feedbackMessages)
    ui.clearScreen()
    print("Rename Address")
    print(string.rep("-", 14))

    local index, errorMessage = ui.chooseEntry(addressBook, feedbackMessages)
    if index == nil then
        printError(errorMessage)
        ui.pause()
        return
    end

    local entry = addressBook[index]
    print()
    print("Current name: " .. entry.name)
    local newName = ui.prompt("New name: ", feedbackMessages)
    if newName == "" then
        printError("Name is required.")
        ui.pause()
        return
    end

    local ok, saveError = address.updateEntry(entry.name, newName, nil)
    if not ok then
        printError(saveError)
        ui.pause()
        return
    end

    reloadAddressBook(addressBook)
    print("Renamed entry to " .. newName .. ".")
    ui.pause()
end

local function editEntry(addressBook, feedbackMessages)
    ui.clearScreen()
    print("Edit Address")
    print(string.rep("-", 12))

    local index, errorMessage = ui.chooseEntry(addressBook, feedbackMessages)
    if index == nil then
        printError(errorMessage)
        ui.pause()
        return
    end

    local entry = addressBook[index]
    print()
    print("Editing: " .. entry.name)
    print("Current address: " .. util.stringifyAddress(entry.address))
    print("Leave blank to keep the current value.")
    print()

    local newName = ui.prompt("Name [" .. entry.name .. "]: ", feedbackMessages)
    if newName ~= "" then
        entry.name = newName
    end

    local newAddress = nil
    local rawAddress = ui.prompt("Address [" .. util.stringifyAddress(entry.address) .. "]: ", feedbackMessages)
    if rawAddress ~= "" then
        local parsedAddress, addressError = address.normalizeAddress(rawAddress)
        if parsedAddress == nil then
            printError(addressError)
            ui.pause()
            return
        end
        newAddress = parsedAddress
    end

    local finalName = newName ~= "" and newName or nil
    local ok, saveError = address.updateEntry(entry.name, finalName, newAddress)
    if not ok then
        printError(saveError)
        ui.pause()
        return
    end

    reloadAddressBook(addressBook)
    print("Updated " .. entry.name .. ".")
    ui.pause()
end

local function performDial(interface, label, addressToUse, feedbackMessages)
    ui.clearScreen()
    print("Dialing: " .. label)
    print(util.stringifyAddress(addressToUse))
    print()

    local ok, result = stargate.dialAddress(interface, util.copyAddress(addressToUse), feedbackMessages)
    if ok then
        print("Dial complete.")
        print("Final feedback: " .. feedback.formatFeedback(feedbackMessages, result))
    else
        printError(result)
    end

    ui.pause()
end

local function autodialSaved(interface, addressBook, feedbackMessages)
    ui.clearScreen()
    print("Autodial Saved Address")
    print(string.rep("-", 21))

    local index, errorMessage = ui.chooseEntry(addressBook, feedbackMessages)
    if index == nil then
        printError(errorMessage)
        ui.pause()
        return
    end

    local entry = addressBook[index]
    performDial(interface, entry.name, entry.address, feedbackMessages)
end

local function manualDial(interface, feedbackMessages)
    ui.clearScreen()
    print("Manual Dial")
    print(string.rep("-", 11))
    print("Enter addresses like -26-6-14-31-11-29-.")
    print("You can also enter 6, 7, or 8 symbols separated by spaces.")
    print("The program will append 0 if needed.")
    print()

    local rawAddress = ui.prompt("Address symbols: ", feedbackMessages)
    local parsedAddress, errorMessage = address.normalizeAddress(rawAddress)
    if parsedAddress == nil then
        printError(errorMessage)
        ui.pause()
        return
    end

    performDial(interface, "Manual address", parsedAddress, feedbackMessages)
end

local function disconnectWormhole(interface, feedbackMessages)
    ui.clearScreen()
    print("Close Wormhole")
    print(string.rep("-", 14))
    print()

    if interface.disconnectStargate == nil then
        printError("disconnectStargate is not available on this interface.")
        ui.pause()
        return
    end

    local wasDisconnected = interface.disconnectStargate()
    if wasDisconnected then
        print("Wormhole closed.")
    else
        printError("Could not close the wormhole. It may already be inactive or still forming.")
    end

    if interface.getRecentFeedback ~= nil then
        local feedbackCode = interface.getRecentFeedback()
        if type(feedbackCode) == "number" then
            print("Feedback: " .. feedback.formatFeedback(feedbackMessages, feedbackCode))
        end
    end

    ui.pause()
end

return {
    addEntry = addEntry,
    removeEntry = removeEntry,
    renameEntry = renameEntry,
    editEntry = editEntry,
    performDial = performDial,
    autodialSaved = autodialSaved,
    manualDial = manualDial,
    disconnectWormhole = disconnectWormhole,
}
