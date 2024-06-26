local http = require('http')
local html = require('html')
local util = require('util')
require('constants')

--- Return all available versions provided by this plugin
--- @param ctx table Empty table used as context, for future extension
--- @return table Descriptions of available versions and accompanying tool descriptions
function PLUGIN:Available(ctx)
    if RUNTIME.osType == 'windows' then
        return GetReleaseListForWindows()
    else
        return GetReleaseListForLinux()
    end
end

function GetReleaseListForWindows()
    local resp, err = http.get({
        url = WIN_URL
    })
    local doc = html.parse(resp.body)

    local result = {}
    doc:find('a'):each(function(i, selection)
        local versionStr = selection:text()
        if util.filter_windows_version(versionStr) then
            local versions = util.split_string(versionStr, '-')
            if util.compare_versions(versions[2], "5.3.2") >= 0 then
                table.insert(result, {
                    version = versions[2],
                    name = versionStr,
                })
            end
        end
    end)
    table.sort(result, function(a, b)
        return util.compare_versions(a.version, b.version) > 0
    end)
    return result
end

function GetReleaseListForLinux()
    local resp, err = http.get({
        url = URL .. '/releases'
    })
    local doc = html.parse(resp.body)

    local result = {}
    doc:find("#layout-content h2"):each(function(i, selection)
        local versionStr = selection:text()
        if util.compare_versions(versionStr, "5.3.2") >= 0 then
            table.insert(result, {
                version = versionStr,
            })
        end
    end)

    table.sort(result, function(a, b)
        return util.compare_versions(a.version, b.version) > 0
    end)
    return result
end
