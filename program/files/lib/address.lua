-- Address normalization and address book management

local util = require("lib.util")
local config = require("lib.config")

local BASE_SYMBOL_COUNT = 6
local MIN_ADDRESS_LENGTH = 7
local MAX_ADDRESS_LENGTH = 9

local serializeJSON = textutils.serialiseJSON or textutils.serializeJSON
local unserializeJSON = textutils.unserialiseJSON or textutils.unserializeJSON

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
    local ok, response = pcall(http.request, url, body, { ["Content-Type"] = "application/json" }, false)
    if not ok then
        return nil, "HTTP request failed: " .. url
    end
    -- http.request is async; use synchronous wrapper via http.put if available
    -- Fallback: use a raw request
    local req = http.request({
        url = url,
        method = "PUT",
        body = body,
        headers = { ["Content-Type"] = "application/json" },
    })
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
    local req = http.request({
        url = url,
        method = "DELETE",
    })
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

local function loadAddressBook()
    local decoded, errorMessage = httpGet("/addresses")
    if decoded == nil then
        return nil, errorMessage
    end

    if type(decoded) ~= "table" or type(decoded.addresses) ~= "table" then
        return nil, "Server returned invalid address book JSON. Expected { addresses = [...] }."
    end

    local entries = decoded.addresses

    local addressBook = {}

    for index = 1, #entries do
        local entry = entries[index]
        if type(entry) == "table" then
            local name = util.trim(tostring(entry.name or ""))
            local address, addressError = normalizeAddress(entry.address)

            if name ~= "" and address ~= nil then
                addressBook[#addressBook + 1] = {
                    name = name,
                    address = address,
                }
            elseif addressError ~= nil then
                printError("Skipping invalid saved entry #" .. index .. ": " .. addressError)
            end
        end
    end

    return addressBook
end

local function saveAddressBook(addressBook)
    -- The HTTP API manages individual entries; this is a no-op bulk save.
    -- Add/edit/remove operations call the API directly via addEntry/updateEntry/removeEntry.
    return true
end

local function addEntry(name, address)
    local _, errorMessage = httpPost("/addresses", { name = name, address = address })
    if errorMessage ~= nil then
        return false, errorMessage
    end
    return true
end

local function updateEntry(oldName, name, address)
    local payload = {}
    if name ~= nil then payload.name = name end
    if address ~= nil then payload.address = address end
    local _, errorMessage = httpPut("/addresses/" .. textutils.urlEncode(oldName), payload)
    if errorMessage ~= nil then
        return false, errorMessage
    end
    return true
end

local function removeEntry(name)
    local _, errorMessage = httpDelete("/addresses/" .. textutils.urlEncode(name))
    if errorMessage ~= nil then
        return false, errorMessage
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
