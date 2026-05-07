-- User interface utilities

local util = require("lib.util")
local events = require("lib.events")
local stargate = require("lib.stargate")

local function clearScreen()
    term.clear()
    term.setCursorPos(1, 1)
end

local function pause(message)
    print(message or "Press Enter to continue...")
    read()
end

local function prompt(message, feedbackMessages)
    write(message)
    return util.trim(read())
end

local function printHeader(interface)
    local version = util.getVersion()
    clearScreen()
    print("Simple Dialing Computer V" .. version)
    print(string.rep("=", 23))
    if interface == nil then
        print("Gate: not connected")
    else
        print("Gate: " .. stargate.describeInterface(interface))
    end
    local summary = events.getLastEventSummary()
    print("Last: " .. (summary or "No events yet"))
    print(string.rep("-", 23))
    print()
end

local function printAddressBook(addressBook)
    if #addressBook == 0 then
        print("No saved addresses.")
        return
    end

    for index = 1, #addressBook do
        local entry = addressBook[index]
        local addressType = "unknown"
        if #entry.address == 7 then
            addressType = "Interstellar"
        elseif #entry.address == 8 then
            addressType = "Intergalactic"
        elseif #entry.address == 9 then
            addressType = "Intergate"
        end
        print(index .. ". " .. entry.name .. " -> " .. util.stringifyAddress(entry.address) .. " (" .. addressType .. ")")
    end
end

local function chooseEntry(addressBook, feedbackMessages)
    if #addressBook == 0 then
        return nil, "Address book is empty."
    end

    printAddressBook(addressBook)
    print()

    local rawIndex = prompt("Select entry number: ", feedbackMessages)
    local index = tonumber(rawIndex)

    if index == nil or index ~= math.floor(index) then
        return nil, "Entry number must be a whole number."
    end

    local entry = addressBook[index]
    if entry == nil then
        return nil, "Entry not found."
    end

    return index, nil
end

return {
    clearScreen = clearScreen,
    pause = pause,
    prompt = prompt,
    printHeader = printHeader,
    printAddressBook = printAddressBook,
    chooseEntry = chooseEntry,
}
