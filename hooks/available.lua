local util = require("util")
require("constants")

--- Return all available versions provided by this plugin
--- @param ctx table Empty table used as context, for future extension
--- @return table Descriptions of available versions and accompanying tool descriptions
function PLUGIN:Available(ctx)
    local manifest = util.fetch_manifest()
    local result = {}

    if RUNTIME.osType == "windows" then
        local arch = util.windows_arch(RUNTIME.archType)
        local seen = {}
        for _, entry in ipairs(manifest.windows or {}) do
            if entry.arch == arch and not seen[entry.version] then
                seen[entry.version] = true
                table.insert(result, { version = entry.version })
            end
        end
    else
        for _, entry in ipairs(manifest.source or {}) do
            table.insert(result, { version = entry.version })
        end
    end

    if #result > 0 then
        result[1].note = "latest"
    end
    return result
end
