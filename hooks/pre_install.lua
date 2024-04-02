local util = require('util')
require('constants')

--- Returns some pre-installed information, such as version number, download address, local files, etc.
--- If checksum is provided, vfox will automatically check it for you.
--- @param ctx table
--- @field ctx.version string User-input version
--- @return table Version information
function PLUGIN:PreInstall(ctx)
    local version = ctx.version

    local lists = self:Available({})
    if version == 'latest' or version == '' then
        version = lists[1].version
    end

    local versions = {}
    for _, value in pairs(lists) do
        if util.starts_with(value.version, version .. '.') then
            versions = value
        end
        if value.version == version then
            versions = value
        end
        if next(versions) ~= nil then
            break
        end
    end
    if next(versions) == nil then
        error('version not found for provided version ' .. version)
    end

    if RUNTIME.osType == 'windows' then
        return GetReleaseForWindows(versions)
    else
        return GetReleaseForLinux(versions)
    end
end

function GetReleaseForWindows(versions)
    return {
        version = versions.version,
        url = WIN_URL .. versions.name,
    }
end

function GetReleaseForLinux(versions)
    return {}
end
