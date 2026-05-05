// Stargate Address Book HTTP Server
// Serves addresses.json via a simple REST API for ComputerCraft

const http = require("http");
const https = require("https");
const fs = require("fs");
const path = require("path");
const packageInfo = require("./package.json");

const PORT = Number(process.env.PORT) || 2088;
const HOST = process.env.HOST || "0.0.0.0";
const DATA_FILE = path.join(__dirname, "addresses.json");
const PROGRAM_UPDATE_ROOT = path.join(__dirname, "updates", "program");
const PROGRAM_MANIFEST_FILE = path.join(PROGRAM_UPDATE_ROOT, "manifest.json");
const PROGRAM_FILES_ROOT = path.join(PROGRAM_UPDATE_ROOT, "files");
const PROGRAM_UPDATE_SOURCE_URL = process.env.PROGRAM_UPDATE_SOURCE_URL || "";
const EMPTY_STORE = { addresses: [] };
let requestCounter = 0;

function writeStore(store) {
    fs.writeFileSync(DATA_FILE, JSON.stringify(store, null, 2), "utf8");
}

function normalizeStore(parsed) {
    // Strict JSON shape: { addresses: [...] }
    if (parsed && typeof parsed === "object" && Array.isArray(parsed.addresses)) {
        return { addresses: parsed.addresses };
    }

    return null;
}

function ensureDataFile() {
    try {
        if (!fs.existsSync(DATA_FILE)) {
            writeStore(EMPTY_STORE);
        }

        fs.accessSync(DATA_FILE, fs.constants.R_OK | fs.constants.W_OK);
        return true;
    } catch (error) {
        console.error("Address book data file is not accessible:", DATA_FILE);
        console.error(error && error.message ? error.message : error);
        return false;
    }
}

function loadStore() {
    if (!ensureDataFile()) {
        throw new Error("Address data file is not accessible.");
    }

    const raw = fs.readFileSync(DATA_FILE, "utf8");
    if (raw.trim() === "") {
        writeStore(EMPTY_STORE);
        return { addresses: [] };
    }

    const parsed = JSON.parse(raw);
    const normalized = normalizeStore(parsed);
    if (normalized == null) {
        writeStore(EMPTY_STORE);
        return { addresses: [] };
    }

    return normalized;
}

function loadAddresses() {
    try {
        const store = loadStore();
        return store.addresses;
    } catch (error) {
        console.error("Failed to read or parse addresses file:", DATA_FILE);
        console.error(error && error.message ? error.message : error);
        return [];
    }
}

function saveAddresses(addresses) {
    if (!ensureDataFile()) {
        throw new Error("Address data file is not writable.");
    }

    writeStore({ addresses });
}

function readBody(req) {
    return new Promise((resolve, reject) => {
        let body = "";
        req.on("data", chunk => { body += chunk; });
        req.on("end", () => resolve(body));
        req.on("error", reject);
    });
}

function sendJSON(res, status, data) {
    const body = JSON.stringify(data);
    res.writeHead(status, {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(body),
        "Access-Control-Allow-Origin": "*",
    });
    res.end(body);
}

function sendError(res, status, message) {
    sendJSON(res, status, { error: message });
}

function getClientAddress(req) {
    const forwardedFor = req.headers["x-forwarded-for"];
    if (typeof forwardedFor === "string" && forwardedFor.length > 0) {
        return forwardedFor.split(",")[0].trim();
    }

    if (Array.isArray(forwardedFor) && forwardedFor.length > 0) {
        return forwardedFor[0];
    }

    return req.socket && req.socket.remoteAddress ? req.socket.remoteAddress : "unknown";
}

function safeReadJSONFile(filePath) {
    if (!fs.existsSync(filePath)) {
        return null;
    }

    try {
        return JSON.parse(fs.readFileSync(filePath, "utf8"));
    } catch {
        return null;
    }
}

function getHttpClient(url) {
    return url.startsWith("https://") ? https : http;
}

function fetchText(url) {
    return new Promise((resolve, reject) => {
        const client = getHttpClient(url);
        client
            .get(url, response => {
                if (response.statusCode && response.statusCode >= 400) {
                    reject(new Error(`HTTP ${response.statusCode} while fetching ${url}`));
                    response.resume();
                    return;
                }

                let body = "";
                response.setEncoding("utf8");
                response.on("data", chunk => {
                    body += chunk;
                });
                response.on("end", () => resolve(body));
            })
            .on("error", reject);
    });
}

async function fetchJSON(url) {
    const text = await fetchText(url);

    try {
        return JSON.parse(text);
    } catch {
        throw new Error(`Invalid JSON from ${url}`);
    }
}

function sendText(res, status, text, contentType) {
    const body = String(text);
    res.writeHead(status, {
        "Content-Type": contentType || "text/plain; charset=utf-8",
        "Content-Length": Buffer.byteLength(body),
        "Access-Control-Allow-Origin": "*",
    });
    res.end(body);
}

function resolveProgramUpdatePath(relativePath) {
    const targetPath = path.resolve(PROGRAM_FILES_ROOT, relativePath);
    const expectedPrefix = PROGRAM_FILES_ROOT + path.sep;

    if (targetPath !== PROGRAM_FILES_ROOT && !targetPath.startsWith(expectedPrefix)) {
        return null;
    }

    return targetPath;
}

function encodePathSegments(relativePath) {
    return relativePath
        .split("/")
        .map(segment => encodeURIComponent(segment))
        .join("/");
}

function normalizeRemoteProgramUpdateSource(sourceUrl) {
    if (typeof sourceUrl !== "string" || sourceUrl.trim() === "") {
        return null;
    }

    const trimmed = sourceUrl.trim();

    try {
        const manifestUrl = trimmed.endsWith("/manifest.json")
            ? trimmed
            : new URL("manifest.json", trimmed.endsWith("/") ? trimmed : `${trimmed}/`).toString();
        const filesBaseUrl = new URL("files/", manifestUrl).toString();

        return {
            manifestUrl,
            filesBaseUrl,
        };
    } catch {
        return null;
    }
}

function resolveRemoteProgramFileUrl(relativePath, sourceConfig, explicitUrl) {
    if (typeof explicitUrl === "string" && explicitUrl.length > 0) {
        try {
            return new URL(explicitUrl, sourceConfig.manifestUrl).toString();
        } catch {
            return null;
        }
    }

    try {
        return new URL(encodePathSegments(relativePath), sourceConfig.filesBaseUrl).toString();
    } catch {
        return null;
    }
}

async function loadProgramManifest(hostHeader) {
    const remoteSource = normalizeRemoteProgramUpdateSource(PROGRAM_UPDATE_SOURCE_URL);
    let rawManifest;

    if (remoteSource != null) {
        console.log(`[updates] Loading remote program manifest from ${remoteSource.manifestUrl}`);
        rawManifest = await fetchJSON(remoteSource.manifestUrl);
    } else {
        console.log(`[updates] Loading local program manifest from ${PROGRAM_MANIFEST_FILE}`);
        rawManifest = safeReadJSONFile(PROGRAM_MANIFEST_FILE);
    }

    return normalizeProgramManifest(rawManifest, hostHeader, remoteSource);
}

async function loadProgramFile(relativePath, hostHeader) {
    const remoteSource = normalizeRemoteProgramUpdateSource(PROGRAM_UPDATE_SOURCE_URL);

    if (remoteSource != null) {
        const manifest = await loadProgramManifest(hostHeader);
        if (manifest == null) {
            throw new Error("Program update manifest is invalid.");
        }

        const fileEntry = manifest.files.find(entry => entry.path === relativePath);
        if (fileEntry == null) {
            console.warn(`[updates] Program file not listed in manifest: ${relativePath}`);
            return null;
        }

        console.log(`[updates] Fetching remote program file ${relativePath} from ${fileEntry.sourceUrl || fileEntry.url}`);
        return fetchText(fileEntry.sourceUrl || fileEntry.url);
    }

    const resolvedPath = resolveProgramUpdatePath(relativePath);
    if (resolvedPath == null) {
        throw new Error("Invalid program update file path.");
    }

    if (!fs.existsSync(resolvedPath) || !fs.statSync(resolvedPath).isFile()) {
        console.warn(`[updates] Local program file not found: ${relativePath}`);
        return null;
    }

    console.log(`[updates] Reading local program file ${relativePath} from ${resolvedPath}`);
    return fs.readFileSync(resolvedPath, "utf8");
}

function normalizeProgramManifest(rawManifest, hostHeader, remoteSource) {
    if (!rawManifest || typeof rawManifest !== "object") {
        return null;
    }

    if (typeof rawManifest.version !== "string" || !Array.isArray(rawManifest.files)) {
        return null;
    }

    const protocol = (process.env.UPDATE_BASE_PROTOCOL || "http").toLowerCase() === "https" ? "https" : "http";

    const files = rawManifest.files
        .map(entry => {
            if (!entry || typeof entry !== "object" || typeof entry.path !== "string") {
                return null;
            }

            const normalizedPath = entry.path.replace(/\\/g, "/");
            const sourceUrl = remoteSource != null
                ? resolveRemoteProgramFileUrl(normalizedPath, remoteSource, entry.url)
                : typeof entry.url === "string" && entry.url.length > 0
                    ? entry.url
                    : null;

            if (remoteSource != null && sourceUrl == null) {
                return null;
            }

            return {
                path: normalizedPath,
                sourceUrl,
                url: typeof entry.url === "string" && entry.url.length > 0
                    ? (remoteSource != null
                        ? `${protocol}://${hostHeader}/updates/program/files/${encodePathSegments(normalizedPath)}`
                        : entry.url)
                    : `${protocol}://${hostHeader}/updates/program/files/${encodePathSegments(normalizedPath)}`,
            };
        })
        .filter(Boolean);

    return {
        version: rawManifest.version,
        files,
    };
}

const server = http.createServer(async (req, res) => {
    const hostHeader = req.headers.host || `localhost:${PORT}`;
    const url = new URL(req.url, `http://${hostHeader}`);
    const pathname = url.pathname;
    const method = req.method;
    const requestId = ++requestCounter;
    const startedAt = Date.now();
    const clientAddress = getClientAddress(req);

    console.log(`[req:${requestId}] ${method} ${pathname}${url.search} from ${clientAddress}`);
    res.on("finish", () => {
        console.log(`[req:${requestId}] ${method} ${pathname} -> ${res.statusCode} (${Date.now() - startedAt}ms)`);
    });

    // OPTIONS preflight
    if (method === "OPTIONS") {
        res.writeHead(204, { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS" });
        res.end();
        return;
    }

    // GET /addresses  - full address store object
    if (method === "GET" && pathname === "/addresses") {
        return sendJSON(res, 200, loadStore());
    }

    // GET /version - server version info
    if (method === "GET" && pathname === "/version") {
        return sendJSON(res, 200, {
            name: packageInfo.name,
            version: packageInfo.version,
        });
    }

    // GET /updates/program/manifest - program update manifest for ComputerCraft clients
    if (method === "GET" && pathname === "/updates/program/manifest") {
        try {
            const normalizedManifest = await loadProgramManifest(hostHeader);
            if (normalizedManifest == null) {
                return sendError(res, 500, "Program update manifest is invalid.");
            }

            return sendJSON(res, 200, normalizedManifest);
        } catch (error) {
            const message = error && error.message ? error.message : String(error);
            const status = message.includes("HTTP 404") ? 404 : 500;
            return sendError(res, status, `Failed to load program update manifest: ${message}`);
        }
    }

    // GET /updates/program/files/:path - raw program file payload
    const programFileMatch = pathname.match(/^\/updates\/program\/files\/(.+)$/);
    if (method === "GET" && programFileMatch) {
        const relativeFilePath = decodeURIComponent(programFileMatch[1]);
        try {
            const fileBody = await loadProgramFile(relativeFilePath, hostHeader);
            if (fileBody == null) {
                return sendError(res, 404, "Program update file not found.");
            }

            return sendText(res, 200, fileBody, "text/plain; charset=utf-8");
        } catch (error) {
            const message = error && error.message ? error.message : String(error);
            if (message === "Invalid program update file path.") {
                return sendError(res, 400, message);
            }

            const status = message.includes("HTTP 404") ? 404 : 500;
            return sendError(res, status, `Failed to load program update file: ${message}`);
        }
    }

    // POST /addresses  - add one  body: { name, address }
    if (method === "POST" && pathname === "/addresses") {
        let body;
        try { body = JSON.parse(await readBody(req)); } catch {
            return sendError(res, 400, "Invalid JSON body.");
        }

        const name = (body.name || "").trim();
        const address = body.address;

        if (!name) return sendError(res, 400, "name is required.");
        if (!Array.isArray(address) || address.length === 0) return sendError(res, 400, "address must be a non-empty array of numbers.");

        const addresses = loadAddresses();

        if (addresses.some(e => e.name.toLowerCase() === name.toLowerCase())) {
            return sendError(res, 409, "An entry with that name already exists.");
        }

        addresses.push({ name, address });
        saveAddresses(addresses);
        return sendJSON(res, 201, { name, address });
    }

    // PUT /addresses/:name  - update by name  body: { name?, address? }
    const putMatch = pathname.match(/^\/addresses\/(.+)$/);
    if (method === "PUT" && putMatch) {
        const targetName = decodeURIComponent(putMatch[1]);
        let body;
        try { body = JSON.parse(await readBody(req)); } catch {
            return sendError(res, 400, "Invalid JSON body.");
        }

        const addresses = loadAddresses();
        const index = addresses.findIndex(e => e.name.toLowerCase() === targetName.toLowerCase());
        if (index === -1) return sendError(res, 404, "Entry not found.");

        if (body.name !== undefined) {
            const newName = body.name.trim();
            if (!newName) return sendError(res, 400, "name cannot be empty.");
            const conflict = addresses.findIndex(e => e.name.toLowerCase() === newName.toLowerCase());
            if (conflict !== -1 && conflict !== index) return sendError(res, 409, "An entry with that name already exists.");
            addresses[index].name = newName;
        }

        if (body.address !== undefined) {
            if (!Array.isArray(body.address) || body.address.length === 0) return sendError(res, 400, "address must be a non-empty array of numbers.");
            addresses[index].address = body.address;
        }

        saveAddresses(addresses);
        return sendJSON(res, 200, addresses[index]);
    }

    // DELETE /addresses/:name  - remove by name
    const deleteMatch = pathname.match(/^\/addresses\/(.+)$/);
    if (method === "DELETE" && deleteMatch) {
        const targetName = decodeURIComponent(deleteMatch[1]);
        const addresses = loadAddresses();
        const index = addresses.findIndex(e => e.name.toLowerCase() === targetName.toLowerCase());
        if (index === -1) return sendError(res, 404, "Entry not found.");

        const [removed] = addresses.splice(index, 1);
        saveAddresses(addresses);
        return sendJSON(res, 200, removed);
    }

    sendError(res, 404, "Not found.");
});

if (!ensureDataFile()) {
    process.exit(1);
}

server.listen(PORT, HOST, () => {
    console.log(`Address book server running at http://${HOST}:${PORT}`);
    console.log(`Data file: ${DATA_FILE}`);
    if (PROGRAM_UPDATE_SOURCE_URL.trim() !== "") {
        console.log(`Program update source: remote (${PROGRAM_UPDATE_SOURCE_URL})`);
    } else {
        console.log(`Program update source: local (${PROGRAM_UPDATE_ROOT})`);
    }
    console.log(`  GET    /addresses          - list all`);
    console.log(`  POST   /addresses          - add entry`);
    console.log(`  PUT    /addresses/:name    - update entry`);
    console.log(`  DELETE /addresses/:name    - remove entry`);
});
