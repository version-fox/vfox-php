local util = require("util")

function PLUGIN:PreInstall(ctx)
    local version = ctx.version
    local versions = self:Available({})
    if #versions == 0 then
        error("No PHP releases available")
    end
    if version == "latest" or version == "" then
        return versions[1]
    end
    if type(version) ~= "string" then
        error("PHP version must be provided")
    end
    -- Exact matches must win over prefixes, especially for Windows TS/NTS.
    for _, release in ipairs(versions) do
        if release.version == version then
            return release
        end
    end
    for _, release in ipairs(versions) do
        if util.starts_with(release.version, version .. ".") then
            return release
        end
    end
    error("PHP version not found: " .. version)
end
