# Auto Update

This project now supports auto updates for both:
- The Node.js server (`master-server`)
- The ComputerCraft program (`program`)

## Server Auto Update

The server updater checks a remote JSON manifest on a schedule.
If the manifest version is newer than the local `.server-version.json`, it downloads files, writes them into `master-server`, and exits so PM2 can restart it.

Configure PM2 env values in `ecosystem.config.js`:
- `AUTO_UPDATE_ENABLED`: `"true"` or `"false"`
- `AUTO_UPDATE_MANIFEST_URL`: URL to a manifest with `{ version, files[] }`
- `AUTO_UPDATE_INTERVAL_MS`: check interval in milliseconds
- `UPDATE_BASE_PROTOCOL`: optional override for generated update URLs (`http` or `https`)

Manifest format example is in `update-manifest.example.json`.

## Program Auto Update

The ComputerCraft program checks `AUTO_UPDATE_MANIFEST_URL` at boot from `program/lib/config.lua`.
If a newer version is found, it downloads all listed files, writes them into the computer filesystem, saves `.program-version.json`, and reboots.

Program config keys:
- `AUTO_UPDATE_ENABLED`
- `AUTO_UPDATE_MANIFEST_URL`
- `AUTO_UPDATE_VERSION_FILE`
- `AUTO_UPDATE_REBOOT_ON_UPDATE`

## Hosting Program Updates From This Server

This server now exposes:
- `GET /updates/program/manifest`
- `GET /updates/program/files/<path>`

Optional server env:
- `PROGRAM_UPDATE_SOURCE_URL`: GitHub raw folder URL or manifest URL for the program release source

By default, the manifest source file is:
- `master-server/updates/program/manifest.json`

By default, the payload files are read from:
- `master-server/updates/program/files/`

You can stage a new program release by replacing files in `updates/program/files`, bumping `updates/program/manifest.json` `version`, then restarting the server.

The manifest can omit `url` for each file. The server will generate file URLs automatically from request host/protocol.

If `PROGRAM_UPDATE_SOURCE_URL` is set, the server will pull `manifest.json` and `files/<path>` from that remote source instead of the local `updates/program` folder. This is intended for GitHub raw URLs, for example:
- `https://raw.githubusercontent.com/<owner>/<repo>/<branch>/program/`
- `https://raw.githubusercontent.com/<owner>/<repo>/<branch>/program/manifest.json`

The server still serves the same local endpoints to clients; it just proxies the release from GitHub.
