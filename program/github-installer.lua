-- GitHub installer for the dialing computer program.
-- Usage:
--   github-installer <github-raw-base-url>
-- Example:
--   github-installer https://raw.githubusercontent.com/Minecrafter8001/dialing-computer-new-the-third-one/main/program

local baseUrl = arg and arg[1]

if not baseUrl or baseUrl == "" then
    baseUrl = "https://raw.githubusercontent.com/Minecrafter8001/dialing-computer-new-the-third-one/main/program"
end

baseUrl = baseUrl:gsub("/+$", "")

local unserializeJSON = textutils.unserialiseJSON or textutils.unserializeJSON

local function get(url)
    local ok, response = pcall(http.get, url)
    if not ok or not response then
        return nil, "Request failed: " .. url
    end

    local body = response.readAll()
    response.close()
    return body, nil
end

local function getJSON(url)
    local body, err = get(url)
    if not body then
        return nil, err
    end

    local decoded = unserializeJSON(body)
    if type(decoded) ~= "table" then
        return nil, "Invalid JSON from " .. url
    end

    return decoded, nil
end

local function ensureDir(filePath)
    local dir = fs.getDir(filePath)
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
end

print("Fetching manifest...")
local manifest, manifestErr = getJSON(baseUrl .. "/manifest.json")
if not manifest then
    printError(manifestErr)
    return
end

if type(manifest.files) ~= "table" then
    printError("Manifest is missing a valid files list")
    return
end

print("Version: " .. tostring(manifest.version or "unknown"))
print("Files: " .. #manifest.files)
print()

for i = 1, #manifest.files do
    local entry = manifest.files[i]
    local filePath = entry.path

    if type(filePath) ~= "string" or filePath == "" then
        printError("Invalid file entry at index " .. i)
        return
    end

    local fileUrl = baseUrl .. "/" .. filePath
    io.write("  " .. filePath .. "...")

    local body, fileErr = get(fileUrl)
    if not body then
        print(" FAILED")
        printError(fileErr)
        return
    end

    ensureDir(filePath)
    local handle = fs.open(filePath, "w")
    if not handle then
        print(" FAILED")
        printError("Could not write " .. filePath)
        return
    end

    handle.write(body)
    handle.close()
    print(" ok")
end

print()
print("Installed version " .. tostring(manifest.version or "unknown") .. ".")
print("Run startup.lua or reboot to start the program.")
