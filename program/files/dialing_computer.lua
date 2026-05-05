-- Simple Dialing Computer for ComputerCraft Stargate Journey mod
-- Main file that orchestrates the dialing interface

local feedback = require("lib.feedback")
local address = require("lib.address")
local stargate = require("lib.stargate")
local ui = require("lib.ui")
local menu = require("lib.menu")
local events = require("lib.events")

local feedbackMessages = {}

local function mainMenuLoop(addressBook, feedbackMessages)
    while true do
        local interface = stargate.findInterface()
        ui.printHeader(interface)
        print("1. Autodial saved address")
        print("2. Manual dial")
        print("3. Add address")
        print("4. Edit address")
        print("5. Rename address")
        print("6. Remove address")
        print("7. Close wormhole")
        print("8. View address book")
        print("9. View event log")
        print("10. Exit")
        print()

        local choice = ui.prompt("Select option: ", feedbackMessages)

        if choice == "1" then
            if interface == nil then
                printError("No basic interface found.")
                ui.pause()
            else
                menu.autodialSaved(interface, addressBook, feedbackMessages)
            end
        elseif choice == "2" then
            if interface == nil then
                printError("No basic interface found.")
                ui.pause()
            else
                menu.manualDial(interface, feedbackMessages)
            end
        elseif choice == "3" then
            menu.addEntry(addressBook, feedbackMessages)
        elseif choice == "4" then
            menu.editEntry(addressBook, feedbackMessages)
        elseif choice == "5" then
            menu.renameEntry(addressBook, feedbackMessages)
        elseif choice == "6" then
            menu.removeEntry(addressBook, feedbackMessages)
        elseif choice == "7" then
            if interface == nil then
                printError("No basic interface found.")
                ui.pause()
            else
                menu.disconnectWormhole(interface, feedbackMessages)
            end
        elseif choice == "8" then
            ui.clearScreen()
            print("Address Book")
            print(string.rep("-", 12))
            ui.printAddressBook(addressBook)
            print()
            ui.pause()
        elseif choice == "9" then
            ui.clearScreen()
            print("Event Log")
            print(string.rep("-", 9))
            local eventLog = events.getEventLog()
            if #eventLog == 0 then
                print("No events logged.")
            else
                for index = 1, #eventLog do
                    local logEntry = eventLog[index]
                    print(index .. ". " .. logEntry.name)
                end
            end
            print()
            ui.pause()
        elseif choice == "10" then
            ui.clearScreen()
            print("Goodbye.")
            return
        else
            printError("Unknown option.")
            ui.pause()
        end
    end
end

local function main()
    -- Load feedback code messages
    local loadedFeedbackMessages, feedbackLoadError = feedback.loadFeedbackMessages()
    if loadedFeedbackMessages == nil then
        error(feedbackLoadError)
    end

    feedbackMessages = loadedFeedbackMessages

    -- Load address book
    local addressBook, loadError = address.loadAddressBook()
    if addressBook == nil then
        error(loadError)
    end

    -- Load event log
    local loadedEventLog, eventLoadError = events.loadEventLog()
    if loadedEventLog == nil then
        -- If event log doesn't exist, start fresh
        loadedEventLog = {}
    end

    -- Run menu and event listener in parallel
    -- The event listener runs in the background while the menu is active
    local function menuWrapper()
        mainMenuLoop(addressBook, feedbackMessages)
    end

    local function eventWrapper()
        events.backgroundEventListener(feedbackMessages)
    end

    -- Run until the menu finishes (returns)
    -- Events will be processed in the background
    parallel.waitForAny(menuWrapper, eventWrapper)
end

main()