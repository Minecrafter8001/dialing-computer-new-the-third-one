-- Auto-update support for the dialing computer program

local serializeJSON = textutils.serialiseJSON or textutils.serializeJSON
local unserializeJSON = textutils.unserialiseJSON or textutils.unserializeJSON

local DEFAULT_VERSION_FILE = ".program-version.json"

local function safeReadJSON(filename)
    if not fs.exists(filename) then
        return nil
    end

    local handle = fs.open(filename, "r")
    if handle == nil then
        return nil
    end

    local contents = handle.readAll()
    handle.close()

    if contents == nil or contents == "" then
        return nil
    end

    local decoded = unserializeJSON(contents)
    if type(decoded) ~= "table" then
        return nil
    end

    return decoded
end

local function safeWriteJSON(filename, value)
    local handle = fs.open(filename, "w")
    if handle == nil then
        return false, "Could not write " .. filename
    end

    handle.write(serializeJSON(value))
    handle.close()

    return true
end

local function isSafeRelativePath(path)
    return type(path) == "string"
        and path ~= ""
        and path:sub(1, 1) ~= "/"
        and path:find("%.%.", 1, true) == nil
end

local function httpGet(url)
    local ok, response = pcall(http.get, url)
    if not ok or response == nil then
        return nil, "HTTP request failed: " .. tostring(url)
    end

    local body = response.readAll()
    response.close()

    return body, nil
end

local function httpGetJSON(url)
    local body, bodyError = httpGet(url)
    if body == nil then
        return nil, bodyError
    end

    local decoded = unserializeJSON(body)
    if type(decoded) ~= "table" then
        return nil, "Server returned invalid JSON."
    end

    return decoded, nil
end

local function ensureParentDir(filePath)
    local parent = fs.getDir(filePath)
    if parent ~= nil and parent ~= "" and not fs.exists(parent) then
        fs.makeDir(parent)
    end
end

local function loadCurrentVersion(versionFile)
    local data = safeReadJSON(versionFile)
    if type(data) ~= "table" then
        return nil
    end

    if type(data.version) ~= "string" then
        return nil
    end

    return data.version
end

local function saveCurrentVersion(versionFile, version)
    return safeWriteJSON(versionFile, {
        version = version,
        updatedAt = os.epoch("utc"),
    })
end

local function fetchManifest(manifestURL)
    local manifest, err = httpGetJSON(manifestURL)
    if manifest == nil then
        return nil, err
    end

    if type(manifest.version) ~= "string" or manifest.version == "" then
        return nil, "Update manifest must include a non-empty version string."
    end

    if type(manifest.files) ~= "table" then
        return nil, "Update manifest must include files table."
    end

    return manifest, nil
end

local function downloadUpdateFiles(files)
    local downloaded = {}

    for index = 1, #files do
        local fileEntry = files[index]
        if type(fileEntry) ~= "table" then
            return nil, "Manifest file entry #" .. tostring(index) .. " is invalid."
        end

        local filePath = fileEntry.path
        local fileURL = fileEntry.url

        if not isSafeRelativePath(filePath) then
            return nil, "Manifest file path is invalid at index " .. tostring(index)
        end

        if type(fileURL) ~= "string" or fileURL == "" then
            return nil, "Manifest file URL is invalid for path " .. filePath
        end

        local body, bodyError = httpGet(fileURL)
        if body == nil then
            return nil, bodyError
        end

        downloaded[#downloaded + 1] = {
            path = filePath,
            body = body,
        }
    end

    return downloaded, nil
end

local function applyUpdateFiles(downloaded)
    for index = 1, #downloaded do
        local item = downloaded[index]
        ensureParentDir(item.path)

        local handle = fs.open(item.path, "w")
        if handle == nil then
            return false, "Could not write update file " .. item.path
        end

        handle.write(item.body)
        handle.close()
    end

    return true, nil
end

local function checkForUpdates(config)
    if config.MASTER_SERVER_ENABLED == false then
        return true, false, "Master server disabled."
    end

    if config.AUTO_UPDATE_ENABLED ~= true then
        return true, false, "Auto-update disabled."
    end

    local manifestURL = config.AUTO_UPDATE_MANIFEST_URL
    if type(manifestURL) ~= "string" or manifestURL == "" then
        return true, false, "Auto-update manifest URL not configured."
    end

    local versionFile = config.AUTO_UPDATE_VERSION_FILE or DEFAULT_VERSION_FILE
    local currentVersion = loadCurrentVersion(versionFile)

    local manifest, manifestError = fetchManifest(manifestURL)
    if manifest == nil then
        return false, false, manifestError
    end

    if currentVersion == manifest.version then
        return true, false, "Already up to date (" .. manifest.version .. ")."
    end

    local downloaded, downloadError = downloadUpdateFiles(manifest.files)
    if downloaded == nil then
        return false, false, downloadError
    end

    local applied, applyError = applyUpdateFiles(downloaded)
    if not applied then
        return false, false, applyError
    end

    local saved, saveError = saveCurrentVersion(versionFile, manifest.version)
    if not saved then
        return false, false, saveError
    end

    return true, true, "Updated to version " .. manifest.version
end

local function runAutoUpdate(config)
    local ok, updated, message = checkForUpdates(config)
    if not ok then
        return false, updated, message
    end

    if updated then
        print(message)

        if config.AUTO_UPDATE_REBOOT_ON_UPDATE ~= false then
            print("Rebooting to apply updates...")
            sleep(0.5)
            os.reboot()
        end
    end

    return true, updated, message
end

return {
    checkForUpdates = checkForUpdates,
    runAutoUpdate = runAutoUpdate,
}
