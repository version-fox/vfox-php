local http = require("http")
local json = require("json")

local M = {}

function M.starts_with(str, prefix)
    return str:sub(1, #prefix) == prefix
end

function M.ends_with(str, suffix)
    return suffix == "" or str:sub(-#suffix) == suffix
end

--- Map vfox archType to the architecture token used in windows.php.net filenames.
function M.windows_arch(arch)
    if arch == "amd64" then return "x64" end
    if arch == "386" then return "x86" end
    return arch
end

local manifest_cache

--- Fetch the version manifest.
---
--- Primary source: the GitHub release asset on the `version-manifest` tag,
--- refreshed by .github/workflows/update-version-list.yaml.
--- Fallback: a `version-manifest.json` shipped inside the plugin directory.
--- The fallback is what CI uses (the test workflows generate the manifest
--- locally before zipping the plugin) and also what kicks in for offline /
--- pre-release-bootstrap installs.
function M.fetch_manifest()
    if manifest_cache then return manifest_cache end

    local githubURL = os.getenv("GITHUB_URL") or "https://github.com/"
    githubURL = githubURL:gsub("/$", "")
    local url = githubURL .. "/version-fox/vfox-php/releases/download/version-manifest/version-manifest.json"

    local resp, err = http.get({ url = url })
    if err == nil and resp and resp.status_code == 200 then
        manifest_cache = json.decode(resp.body)
        return manifest_cache
    end

    local local_path = RUNTIME.pluginDirPath .. "/version-manifest.json"
    local content, read_err = M.read_file(local_path)
    if read_err == nil and content ~= "" then
        manifest_cache = json.decode(content)
        return manifest_cache
    end

    local detail
    if err ~= nil then
        detail = err
    else
        detail = "HTTP " .. tostring(resp.status_code) .. " for " .. url
    end
    error("Failed to fetch version manifest: " .. detail
        .. " (no fallback at " .. local_path .. ")")
end

function M.read_file(filename)
    local file = io.open(filename, "r")
    if not file then
        return "", "Failed to open file: " .. filename
    end
    local content = file:read("*a")
    file:close()
    return content
end

function M.write_file(filename, content)
    local file = io.open(filename, "w")
    if not file then
        return false, "Failed to open file for writing: " .. filename
    end
    file:write(content)
    file:close()
    return true
end

return M
