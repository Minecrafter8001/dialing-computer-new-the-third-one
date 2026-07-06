-- Configuration for the dialing computer
-- Edit ADDRESS_SERVER_URL to point to your address book server

return {
    MASTER_SERVER_ENABLED = false,
    ADDRESS_SERVER_URL = "",
    ADDRESS_BOOK_SERVER_ENABLED = true,
    ADDRESS_BOOK_FILENAME = "address_book.json",
    AUTO_UPDATE_ENABLED = true,
    AUTO_UPDATE_MANIFEST_URL = "",
    AUTO_UPDATE_VERSION_FILE = ".program-version.json",
    AUTO_UPDATE_REBOOT_ON_UPDATE = true,
    AUTO_UPDATE_CHECK_INTERVAL = 30,
}
