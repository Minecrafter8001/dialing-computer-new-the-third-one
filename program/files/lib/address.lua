-- Address normalization and address book management

local util = require("lib.util")
local config = require("lib.config")

local BASE_SYMBOL_COUNT = 6
local MIN_ADDRESS_LENGTH = 7
local MAX_ADDRESS_LENGTH = 9
local DEFAULT_LOCAL_ADDRESS_BOOK_FILE = "address_book_local.json"

local serializeJSON = textutils.serialiseJSON or textutils.serializeJSON
local unserializeJSON = textutils.unserialiseJSON or textutils.unserializeJSON

local function getLocalAddressBookFile()
    local fileName = config.ADDRESS_BOOK_FILENAME
    if type(fileName) == "string" and fileName ~= "" then
        return fileName
    end

    return DEFAULT_LOCAL_ADDRESS_BOOK_FILE
end

local function isMasterServerEnabled()
    return config.MASTER_SERVER_ENABLED ~= false
end

local function isAddressBookServerEnabled()
    if not isMasterServerEnabled() then
        return false
    end

    return config.ADDRESS_BOOK_SERVER_ENABLED ~= false
end

local function getBaseURL()
    return config.ADDRESS_SERVER_URL or "http://localhost:8088"
end

local function httpGet(path)
    local url = getBaseURL() .. path
    local ok, response = pcall(http.get, url)
    if not ok or not response then
        return nil, "HTTP request failed: " .. url
    end

    local body = response.readAll()
    response.close()

    local decoded = unserializeJSON(body)
    if decoded == nil then
        return nil, "Server returned invalid JSON."
    end

    return decoded, nil
end

local function httpPost(path, payload)
    local url = getBaseURL() .. path
    local body = serializeJSON(payload)
    local ok, response = pcall(http.post, url, body, { ["Content-Type"] = "application/json" })
    if not ok or not response then
        return nil, "HTTP request failed: " .. url
    end

    local responseBody = response.readAll()
    local status = response.getResponseCode()
    response.close()

    local decoded = unserializeJSON(responseBody)
    if decoded == nil then
        return nil, "Server returned invalid JSON."
    end

    if status >= 400 then
        return nil, decoded.error or ("Server error " .. status)
    end

    return decoded, nil
end

local function httpPut(path, payload)
    local url = getBaseURL() .. path
    local body = serializeJSON(payload)

    local ok = pcall(http.request, {
        url = url,
        method = "PUT",
        body = body,
        headers = { ["Content-Type"] = "application/json" },
    })

    if not ok then
        return nil, "HTTP request failed: " .. url
    end

    local event
    repeat
        event = { os.pullEvent() }
    until event[1] == "http_success" or event[1] == "http_failure"

    if event[1] == "http_failure" then
        return nil, "HTTP PUT failed: " .. url
    end

    local responseBody = event[3].readAll()
    local status = event[3].getResponseCode()
    event[3].close()

    local decoded = unserializeJSON(responseBody)
    if decoded == nil then
        return nil, "Server returned invalid JSON."
    end

    if status >= 400 then
        return nil, decoded.error or ("Server error " .. status)
    end

    return decoded, nil
end

local function httpDelete(path)
    local url = getBaseURL() .. path

    local ok = pcall(http.request, {
        url = url,
        method = "DELETE",
    })

    if not ok then
        return nil, "HTTP request failed: " .. url
    end

    local event
    repeat
        event = { os.pullEvent() }
    until event[1] == "http_success" or event[1] == "http_failure"

    if event[1] == "http_failure" then
        return nil, "HTTP DELETE failed: " .. url
    end

    local responseBody = event[3].readAll()
    local status = event[3].getResponseCode()
    event[3].close()

    local decoded = unserializeJSON(responseBody)
    if decoded == nil then
        return nil, "Server returned invalid JSON."
    end

    if status >= 400 then
        return nil, decoded.error or ("Server error " .. status)
    end

    return decoded, nil
end

local function normalizeAddress(input)
    if type(input) == "table" then
        local normalized = {}

        for index = 1, #input do
            local value = tonumber(input[index])
            if value == nil then
                return nil, "Address contains a non-numeric symbol."
            end

            if value ~= math.floor(value) then
                return nil, "Address symbols must be whole numbers."
            end

            if value < 0 or value > 38 then
                return nil, "Address symbols must be between 0 and 38."
            end

            normalized[#normalized + 1] = value
        end

        if normalized[#normalized] ~= 0 then
            normalized[#normalized + 1] = 0
        end

        if #normalized < MIN_ADDRESS_LENGTH or #normalized > MAX_ADDRESS_LENGTH then
            return nil, "Address must contain 7, 8, or 9 chevrons including the point of origin."
        end

        if normalized[#normalized] ~= 0 then
            return nil, "The last symbol must be 0 for the point of origin."
        end

        return normalized
    end

    if type(input) ~= "string" then
        return nil, "Address must be text or a table of numbers."
    end

    local parts = util.splitAddress(input)
    return normalizeAddress(parts)
end

local function parseEntries(entries)
    if type(entries) ~= "table" then
        return nil, "Address book JSON is invalid. Expected an array of entries."
    end

    local parsed = {}

    for index = 1, #entries do
        local entry = entries[index]
        if type(entry) == "table" then
            local name = util.trim(tostring(entry.name or ""))
            local normalizedAddress, addressError = normalizeAddress(entry.address)

            if name ~= "" and normalizedAddress ~= nil then
                parsed[#parsed + 1] = {
                    name = name,
                    address = normalizedAddress,
                }
            elseif addressError ~= nil then
                printError("Skipping invalid saved entry #" .. index .. ": " .. addressError)
            end
        end
    end

    return parsed, nil
end

local function loadLocalAddressBook()
    local decoded, fileError = util.loadJSONFile(getLocalAddressBookFile())
    if decoded == nil then
        return nil, fileError
    end

    local entries = decoded
    if type(decoded) == "table" and type(decoded.addresses) == "table" then
        entries = decoded.addresses
    end

    return parseEntries(entries)
end

local function saveLocalAddressBook(addressBook)
    local serialized = {}

    for index = 1, #addressBook do
        local entry = addressBook[index]
        serialized[index] = {
            name = entry.name,
            address = util.copyAddress(entry.address),
        }
    end

    return util.saveJSONFile(getLocalAddressBookFile(), {
        addresses = serialized,
        updatedAt = os.epoch("utc"),
    })
end

local function findEntryIndex(addressBook, name)
    for index = 1, #addressBook do
        if addressBook[index].name == name then
            return index
        end
    end

    return nil
end

local function loadAddressBook()
    local localAddressBook, localError = loadLocalAddressBook()
    if localAddressBook == nil then
        return nil, localError
    end

    if not isAddressBookServerEnabled() then
        return localAddressBook
    end

    local decoded, _ = httpGet("/addresses")
    if decoded == nil then
        return localAddressBook
    end

    if type(decoded) ~= "table" or type(decoded.addresses) ~= "table" then
        return localAddressBook
    end

    local parsed, parseError = parseEntries(decoded.addresses)
    if parsed == nil then
        return localAddressBook
    end

    -- Keep a local mirror so the program can keep running offline.
    saveLocalAddressBook(parsed)
    return parsed
end

local function saveAddressBook(addressBook)
    return saveLocalAddressBook(addressBook)
end

local function addEntry(name, address)
    local normalizedAddress, normalizeError = normalizeAddress(address)
    if normalizedAddress == nil then
        return false, normalizeError
    end

    local localAddressBook, loadError = loadLocalAddressBook()
    if localAddressBook == nil then
        return false, loadError
    end

    if findEntryIndex(localAddressBook, name) ~= nil then
        return false, "Address already exists: " .. name
    end

    localAddressBook[#localAddressBook + 1] = {
        name = name,
        address = normalizedAddress,
    }

    local saved, saveError = saveLocalAddressBook(localAddressBook)
    if not saved then
        return false, saveError
    end

    if isAddressBookServerEnabled() then
        httpPost("/addresses", { name = name, address = normalizedAddress })
    end

    return true
end

local function updateEntry(oldName, name, address)
    local payload = {}
    if name ~= nil then
        payload.name = name
    end

    local normalizedAddress = nil
    if address ~= nil then
        local normalizeError
        normalizedAddress, normalizeError = normalizeAddress(address)
        if normalizedAddress == nil then
            return false, normalizeError
        end
        payload.address = normalizedAddress
    end

    local localAddressBook, loadError = loadLocalAddressBook()
    if localAddressBook == nil then
        return false, loadError
    end

    local index = findEntryIndex(localAddressBook, oldName)
    if index == nil then
        return false, "Address not found: " .. oldName
    end

    if name ~= nil and name ~= "" and name ~= oldName then
        if findEntryIndex(localAddressBook, name) ~= nil then
            return false, "Address already exists: " .. name
        end
        localAddressBook[index].name = name
    end

    if normalizedAddress ~= nil then
        localAddressBook[index].address = normalizedAddress
    end

    local saved, saveError = saveLocalAddressBook(localAddressBook)
    if not saved then
        return false, saveError
    end

    if isAddressBookServerEnabled() then
        httpPut("/addresses/" .. textutils.urlEncode(oldName), payload)
    end

    return true
end

local function removeEntry(name)
    local localAddressBook, loadError = loadLocalAddressBook()
    if localAddressBook == nil then
        return false, loadError
    end

    local index = findEntryIndex(localAddressBook, name)
    if index == nil then
        return false, "Address not found: " .. name
    end

    table.remove(localAddressBook, index)

    local saved, saveError = saveLocalAddressBook(localAddressBook)
    if not saved then
        return false, saveError
    end

    if isAddressBookServerEnabled() then
        httpDelete("/addresses/" .. textutils.urlEncode(name))
    end

    return true
end

return {
    BASE_SYMBOL_COUNT = BASE_SYMBOL_COUNT,
    MIN_ADDRESS_LENGTH = MIN_ADDRESS_LENGTH,
    MAX_ADDRESS_LENGTH = MAX_ADDRESS_LENGTH,
    normalizeAddress = normalizeAddress,
    loadAddressBook = loadAddressBook,
    saveAddressBook = saveAddressBook,
    addEntry = addEntry,
    updateEntry = updateEntry,
    removeEntry = removeEntry,
}
