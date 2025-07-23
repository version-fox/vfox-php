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
    local result = {}
    local urls = { WIN_RELEASES_URL, WIN_RELEASES_URL_LTS }

    for _, url in ipairs(urls) do
        local resp, err = http.get({ url = url })

        if resp then
            local doc = html.parse(resp.body)
            local versions = {}
            doc:find('a'):each(function(i, selection)
                local versionStr = selection:text()
                table.insert(versions, versionStr)
            end)
            -- TODO like this because for some reason sorting it at the end resets is_from_lts to false
            table.sort(versions, function(a, b)
                return util.compare_versions(a, b) > 0
            end)
            for _, versionStr in ipairs(versions) do
                if util.filter_windows_version(versionStr) then
                    local versions = util.split_string(versionStr, '-')
                    if util.compare_versions(versions[2], "5.3.2") >= 0 then
                        local entry = {
                            version = (versions[3] ~= "nts") and versions[2] or versions[2] .. "-nts",
                            name = versionStr
                        }

                        entry.is_from_lts = (url == WIN_RELEASES_URL_LTS)
                        table.insert(result, entry)
                    end
                end
            end
        end
    end

    return result
end

function GetReleaseListForLinux()
    local result = {}
    local urls = { RELEASES_URL, RELEASES_URL_LTS }

    for _, url in ipairs(urls) do
        local resp, err = http.get({ url = url })
        local is_from_lts = (url == RELEASES_URL_LTS)

        if resp then
            local doc = html.parse(resp.body)
            local query = "#layout-content " .. (is_from_lts and "h3" or "h2")
            doc:find(query):each(function(i, selection)
                local versionStr = is_from_lts and selection:attr("id") or selection:text()
                versionStr = versionStr:gsub("^v", "")
                if util.compare_versions(versionStr, "5.3.2") >= 0 then
                    table.insert(result, {
                        version = versionStr,
                    })
                end
            end)
        end
    end

    table.sort(result, function(a, b)
        return util.compare_versions(a.version, b.version) > 0
    end)
    return result
end
