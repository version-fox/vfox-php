local http = require("http")
local json = require("json")
local html = require("html")
local util = require("util")
local releases = {}

local function fetch(url)
    local response, err = http.get({ url = url })
    if err ~= nil or response == nil then
        error("Failed to fetch PHP releases from " .. url .. ": " .. tostring(err or "empty response"))
    end
    if response.status_code ~= 200 then
        error("Failed to fetch PHP releases from " .. url .. ": HTTP " .. tostring(response.status_code))
    end
    return response.body
end

local function sort(result)
    table.sort(result, function(a, b)
        local order = util.compare_versions(a.version:match("^[%d.]+"), b.version:match("^[%d.]+"))
        if order ~= 0 then
            return order > 0
        end
        -- Plain versions are thread-safe on Windows; prefer them for latest.
        return a.version < b.version
    end)
    if #result == 0 then
        error("No PHP releases found for " .. RUNTIME.osType .. "/" .. RUNTIME.archType)
    end
    return result
end

local function windows()
    local arch = ({ amd64 = "x64", ["386"] = "x86", arm64 = "arm64" })[RUNTIME.archType]
    if not arch then
        error("Unsupported PHP architecture: " .. tostring(RUNTIME.archType))
    end
    local result, seen = {}, {}
    -- Current releases win when the same version also exists in the archive.
    for _, base in ipairs({
        "https://windows.php.net/downloads/releases/",
        "https://windows.php.net/downloads/releases/archives/",
    }) do
        html.parse(fetch(base)):find("a"):each(function(_, selection)
            local filename = (selection:attr("href") or ""):match("([^/]+)$") or ""
            local version, variant, fileArch =
                filename:match("^php%-(%d+%.%d+%.%d+)(.-)%-Win32%-[Vv][CcSs]%d+%-(%w+)%.zip$")
            if not version or fileArch ~= arch then
                return
            end
            local rebuild = variant:match("^%-(%d+)$") or variant:match("^%-nts%-(%d+)$")
            if variant ~= "" and variant ~= "-nts" and not rebuild then
                return
            end
            local nts = variant:match("^%-nts") ~= nil
            rebuild = tonumber(rebuild) or 0
            if util.compare_versions(version, "5.3.2") < 0 then
                return
            end
            version = version .. (nts and "-nts" or "")
            if not seen[version] then
                local entry = { version = version, url = base .. filename, note = nts and "NTS" or "TS" }
                seen[version] = { entry = entry, base = base, rebuild = rebuild }
                table.insert(result, entry)
            elseif seen[version].base == base and rebuild > seen[version].rebuild then
                seen[version].entry.url = base .. filename
                seen[version].rebuild = rebuild
            end
        end)
    end
    return sort(result)
end

local function source()
    local result, seen = {}, {}
    for _, major in ipairs({ 8, 7, 5 }) do
        local url = "https://www.php.net/releases/index.php?json&max=10000&version=" .. major
        local decoded = json.decode(fetch(url))
        if type(decoded) ~= "table" then
            error("Invalid PHP release index from " .. url)
        end
        for version, release in pairs(decoded) do
            if
                type(version) == "string"
                and version:match("^%d+%.%d+%.%d+$")
                and util.compare_versions(version, "5.3.2") >= 0
                and type(release) == "table"
                and type(release.source) == "table"
                and not seen[version]
            then
                for _, file in ipairs(release.source) do
                    if file.filename == "php-" .. version .. ".tar.gz" then
                        seen[version] = true
                        table.insert(result, {
                            version = version,
                            url = "https://www.php.net/distributions/" .. file.filename,
                            sha256 = file.sha256,
                            md5 = file.md5,
                        })
                        break
                    end
                end
            end
        end
    end
    return sort(result)
end

function releases.available()
    if RUNTIME.osType == "windows" then
        return windows()
    end
    return source()
end

return releases
