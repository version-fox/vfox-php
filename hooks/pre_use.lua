-- Copyright 2026 Han Li and contributors
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--   http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local util = require("util")

--- The pattern of the installed names that a line or a major selects: the plain
--- names of its releases, which carry no -zts or -nts. Nil for any other version.
local function plain_builds(version)
    local major, minor = version:match("^(%d+)%.(%d+)$")
    if major then
        return "^" .. major .. "%." .. minor .. "%.%d+$"
    end
    major = version:match("^(%d+)$")
    if major then
        return "^" .. major .. "%.%d+%.%d+$"
    end
    return nil
end

--- Chooses the installed PHP that vfox use takes for the version. A line or a
--- major takes the newest installed build of the default type, the plain name:
--- the TS build on Windows, the NTS build on Linux and macOS. A full release, or
--- a name with -zts or -nts, is taken as it is. When nothing installed matches,
--- the version is returned as typed, and vfox reports it as not installed.
--- vfox's own fuzzy match would take a build of another type, because it matches
--- the prefix of any installed name.
function PLUGIN:PreUse(ctx)
    local version = ctx.version or ""
    if version == "" then
        return nil
    end
    local pattern = plain_builds(version)
    if not pattern then
        return { version = version }
    end
    local newest
    for name in pairs(ctx.installedSdks or {}) do
        if name:match(pattern) and (not newest or util.compare_versions(name, newest) > 0) then
            newest = name
        end
    end
    return { version = newest or version }
end
