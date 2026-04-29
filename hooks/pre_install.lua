local util = require("util")
require("constants")

--- Returns some pre-installed information, such as version number, download address, local files, etc.
--- If checksum is provided, vfox will automatically check it for you.
--- @param ctx table
--- @field ctx.version string User-input version
--- @return table Version information
function PLUGIN:PreInstall(ctx)
    local version = ctx.version
    local manifest = util.fetch_manifest()

    if RUNTIME.osType == "windows" then
        return WindowsPreInstall(manifest, version)
    else
        return SourcePreInstall(manifest, version)
    end
end

local function find_match(list, version, predicate)
    if version == "" or version == "latest" then
        for _, e in ipairs(list) do
            if not predicate or predicate(e) then
                return e
            end
        end
        return nil
    end
    for _, e in ipairs(list) do
        if e.version == version and (not predicate or predicate(e)) then
            return e
        end
    end
    local prefix = version .. "."
    for _, e in ipairs(list) do
        if util.starts_with(e.version, prefix) and (not predicate or predicate(e)) then
            return e
        end
    end
    return nil
end

function SourcePreInstall(manifest, version)
    local entry = find_match(manifest.source or {}, version, nil)
    if not entry then
        error("PHP source release not found for version: " .. tostring(version))
    end
    local result = {
        version = entry.version,
        url = PHP_DIST_URL .. entry.filename,
    }
    if entry.sha256 and entry.sha256 ~= "" then
        result.sha256 = entry.sha256
    end
    if entry.md5 and entry.md5 ~= "" then
        result.md5 = entry.md5
    end
    return result
end

function WindowsPreInstall(manifest, version)
    local arch = util.windows_arch(RUNTIME.archType)
    local entry = find_match(manifest.windows or {}, version, function(e)
        return e.arch == arch and not e.nts
    end)
    if not entry and version ~= "" and version ~= "latest" then
        -- The user may have explicitly requested an NTS build (e.g. "8.5.5-nts").
        entry = find_match(manifest.windows or {}, version, function(e)
            return e.arch == arch
        end)
    end
    if not entry then
        error("PHP Windows binary not found for version " .. tostring(version) .. " (arch=" .. tostring(arch) .. ")")
    end
    local base = entry.current and PHP_WIN_RELEASES or PHP_WIN_ARCHIVES
    return {
        version = entry.version,
        url = base .. entry.filename,
    }
end
