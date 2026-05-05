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

    handle.write(serializeJSON(data))
    handle.close()

    return true
end

local function loadJSONFile(filename)
    if not fs.exists(filename) then
        return {}, nil
    end

    local handle = fs.open(filename, "r")
    if handle == nil then
        return nil, "Could not open " .. filename
    end

    local contents = handle.readAll()
    handle.close()

    if contents == nil or contents == "" then
        return {}, nil
    end

    local decoded = unserializeJSON(contents)
    if type(decoded) ~= "table" then
        return nil, "JSON is invalid."
    end

    return decoded, nil
end

local function setDialedAddress(address)
    lastDialedAddress = address
end

local function getDialedAddress()
    return lastDialedAddress
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
}
