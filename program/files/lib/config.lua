-- Configuration for the dialing computer
-- Edit ADDRESS_SERVER_URL to point to your address book server

return {
    ADDRESS_SERVER_URL = "http://192.168.1.206:2088",
    AUTO_UPDATE_ENABLED = true,
    AUTO_UPDATE_MANIFEST_URL = "http://192.168.1.206:2088/updates/program/manifest",
    AUTO_UPDATE_VERSION_FILE = ".program-version.json",
    AUTO_UPDATE_REBOOT_ON_UPDATE = true,
    AUTO_UPDATE_CHECK_INTERVAL = 30, -- seconds between periodic update checks
}
