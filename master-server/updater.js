const fs = require("fs");
const path = require("path");
const http = require("http");
const https = require("https");

const VERSION_FILE = path.join(__dirname, ".server-version.json");

const updateState = {
  enabled: false,
  checking: false,
  lastCheckAt: null,
  lastStatus: "idle",
  currentVersion: null,
  latestVersion: null,
  lastError: null,
};

let intervalHandle = null;

function readLocalVersion() {
  if (!fs.existsSync(VERSION_FILE)) {
    return null;
  }

  try {
    const parsed = JSON.parse(fs.readFileSync(VERSION_FILE, "utf8"));
    return typeof parsed.version === "string" ? parsed.version : null;
  } catch {
    return null;
  }
}

function writeLocalVersion(version) {
  fs.writeFileSync(
    VERSION_FILE,
    JSON.stringify({ version, updatedAt: new Date().toISOString() }, null, 2),
    "utf8",
  );
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
  let parsed;

  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error(`Invalid JSON from ${url}`);
  }

  return parsed;
}

function isSafeRelativePath(relativePath) {
  return (
    typeof relativePath === "string" &&
    relativePath.length > 0 &&
    !path.isAbsolute(relativePath) &&
    !relativePath.includes("..")
  );
}

function resolveSafePath(relativePath) {
  const targetPath = path.resolve(__dirname, relativePath);
  const expectedPrefix = __dirname + path.sep;

  if (targetPath !== __dirname && !targetPath.startsWith(expectedPrefix)) {
    return null;
  }

  return targetPath;
}

async function loadManifest(manifestUrl) {
  const manifest = await fetchJSON(manifestUrl);

  if (!manifest || typeof manifest !== "object") {
    throw new Error("Update manifest must be an object.");
  }

  if (typeof manifest.version !== "string" || manifest.version.length === 0) {
    throw new Error("Update manifest must include a non-empty version.");
  }

  if (!Array.isArray(manifest.files)) {
    throw new Error("Update manifest must include files array.");
  }

  return manifest;
}

async function downloadFiles(files) {
  const downloaded = [];

  for (let index = 0; index < files.length; index += 1) {
    const fileEntry = files[index];

    if (!fileEntry || typeof fileEntry !== "object") {
      throw new Error(`Manifest entry ${index} is invalid.`);
    }

    const relativePath = fileEntry.path;
    const url = fileEntry.url;

    if (!isSafeRelativePath(relativePath)) {
      throw new Error(`Manifest path is invalid at entry ${index}.`);
    }

    if (typeof url !== "string" || url.length === 0) {
      throw new Error(`Manifest URL is invalid for file ${relativePath}.`);
    }

    const fileBody = await fetchText(url);
    downloaded.push({
      path: relativePath,
      body: fileBody,
    });
  }

  return downloaded;
}

function applyFiles(downloadedFiles) {
  for (let index = 0; index < downloadedFiles.length; index += 1) {
    const fileEntry = downloadedFiles[index];
    const targetPath = resolveSafePath(fileEntry.path);

    if (targetPath == null) {
      throw new Error(`Refusing to write outside server folder: ${fileEntry.path}`);
    }

    fs.mkdirSync(path.dirname(targetPath), { recursive: true });
    fs.writeFileSync(targetPath, fileEntry.body, "utf8");
  }
}

async function runUpdateCheck(options) {
  const logger = options.logger || console;

  if (!options.enabled) {
    updateState.enabled = false;
    updateState.lastStatus = "disabled";
    return;
  }

  if (updateState.checking) {
    return;
  }

  if (typeof options.manifestUrl !== "string" || options.manifestUrl.length === 0) {
    updateState.enabled = true;
    updateState.lastStatus = "error";
    updateState.lastError = "AUTO_UPDATE_MANIFEST_URL is not set.";
    return;
  }

  updateState.enabled = true;
  updateState.checking = true;
  updateState.lastCheckAt = new Date().toISOString();
  updateState.lastError = null;
  updateState.currentVersion = readLocalVersion();

  try {
    const manifest = await loadManifest(options.manifestUrl);
    updateState.latestVersion = manifest.version;

    if (updateState.currentVersion === manifest.version) {
      updateState.lastStatus = "up-to-date";
      return;
    }

    const downloadedFiles = await downloadFiles(manifest.files);
    applyFiles(downloadedFiles);
    writeLocalVersion(manifest.version);

    updateState.currentVersion = manifest.version;
    updateState.lastStatus = "updated";

    logger.log(`Auto-update applied to version ${manifest.version}.`);

    if (typeof options.onUpdated === "function") {
      options.onUpdated(manifest.version);
    }
  } catch (error) {
    updateState.lastStatus = "error";
    updateState.lastError = error && error.message ? error.message : String(error);
    logger.error("Auto-update check failed:", updateState.lastError);
  } finally {
    updateState.checking = false;
  }
}

function startAutoUpdate(options) {
  if (intervalHandle != null) {
    clearInterval(intervalHandle);
    intervalHandle = null;
  }

  runUpdateCheck(options);

  const intervalMs = Number(options.intervalMs) || 300000;
  intervalHandle = setInterval(() => {
    runUpdateCheck(options);
  }, intervalMs);
}

function getUpdateState() {
  return { ...updateState };
}

module.exports = {
  startAutoUpdate,
  getUpdateState,
};
