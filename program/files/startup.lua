local config = require("lib.config")
local updater = require("lib.updater")

local ok, _, message = updater.runAutoUpdate(config)
if not ok and message ~= nil then
	print("Auto-update check failed: " .. message)
end

shell.run("dialing_computer")