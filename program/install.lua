-- Installer: downloads the dialing computer program from the server.
-- Usage: install <server-url>
-- Example: install http://192.168.1.206:2088

local serverUrl = arg and arg[1]

if not serverUrl or serverUrl == "" then
    serverUrl = "http://192.168.1.206:2088"
end

serverUrl = serverUrl:gsub("/+$", "")

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
    if not body then return nil, err end
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
local manifest, manifestErr = getJSON(serverUrl .. "/updates/program/manifest")
if not manifest then
    printError(manifestErr)
    return
end

print("Version: " .. manifest.version)
print("Files: " .. #manifest.files)
print()

for i = 1, #manifest.files do
    local entry = manifest.files[i]
    local filePath = entry.path
    local fileUrl = entry.url

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
print("Installed version " .. manifest.version .. ".")
for i = 1, 5 do
    print("Rebooting in " .. (6 - i) .. " seconds...")
    local x,y = term.getCursorPos()
    term.setCursorPos(1, y - 1)
    
    term.clearLine()
    sleep(1)
end
os.reboot()