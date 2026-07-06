-- Utility functions for string and data manipulation

local serializeJSON = textutils.serialiseJSON or textutils.serializeJSON
local unserializeJSON = textutils.unserialiseJSON or textutils.unserializeJSON

local lastDialedAddress = nil

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function splitAddress(input)
    local parts = {}

    if input:find("-") ~= nil then
        for token in input:gmatch("%-(%d+)") do
            parts[#parts + 1] = token
        end

        if #parts > 0 then
            return parts
        end
    end

    for token in input:gmatch("[^,%s]+") do
        parts[#parts + 1] = token
    end

    return parts
end

local function copyAddress(address)
    local copied = {}

    for index = 1, #address do
        copied[index] = address[index]
    end

    return copied
end

local function stringifyAddress(address)
    return "-" .. table.concat(address, "-") .. "-"
end

local function serializeAddressBook(addressBook)
    local serialized = {}

    for index = 1, #addressBook do
        local entry = addressBook[index]
        serialized[index] = {
            name = entry.name,
            address = stringifyAddress(entry.address),
        }
    end

    return serialized
end

local function saveJSONFile(filename, data)
    local handle = fs.open(filename, "w")
    if handle == nil then
        return false, "Could not write " .. filename
    end

    local encoded, encodeError = serializeJSON(data)
    if encoded == nil then
        handle.close()
        return false, "Could not encode JSON for " .. filename .. ": " .. tostring(encodeError)
    end

    handle.write(encoded)
    handle.close()

    return true
end

local function loadJSONFile(filename)
    if not fs.exists(filename) then
        return nil, "File does not exist: " .. filename
    end

    local handle = fs.open(filename, "r")
    if handle == nil then
        return nil, "Could not open " .. filename
    end

    local contents = handle.readAll()
    handle.close()

    if contents == nil or contents:match("^%s*$") then
        return nil, "File is empty: " .. filename
    end

    local ok, decoded, decodeError = pcall(unserializeJSON, contents)
    if not ok then
        return nil, "JSON parse failed in " .. filename .. ": " .. tostring(decoded)
    end

    if decoded == nil then
        return nil, "JSON is invalid in " .. filename .. ": " .. tostring(decodeError)
    end

    if type(decoded) ~= "table" then
        return nil, "JSON root must be an object or array in " .. filename
    end

    return decoded, nil
end


local function setDialedAddress(address)
    lastDialedAddress = address
end

local function getDialedAddress()
    return lastDialedAddress
end

local function getVersion()
    local manifest, errorMessage = loadJSONFile("manifest.json")

    if manifest == nil then
        return "unknown (failed to load manifest: " .. tostring(errorMessage) .. ")"
    end

    if manifest.version == nil then
        return "unknown (manifest.json has no 'version' field)"
    end

    return manifest.version
end


return {
    trim = trim,
    splitAddress = splitAddress,
    copyAddress = copyAddress,
    stringifyAddress = stringifyAddress,
    serializeAddressBook = serializeAddressBook,
    saveJSONFile = saveJSONFile,
    loadJSONFile = loadJSONFile,
    setDialedAddress = setDialedAddress,
    getDialedAddress = getDialedAddress,
    getVersion = getVersion,
}
