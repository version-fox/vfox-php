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
    -- On Linux and macOS, -zts names the thread-safe build of a full release. It is
    -- built from the release's own source, so the list does not show it separately.
    -- Windows has no -zts build: there, the plain version is TS.
    local base = RUNTIME.osType ~= "windows" and version:match("^(%d+%.%d+%.%d+)%-zts$")
    if base then
        for _, entry in ipairs(versions) do
            if entry.version == base then
                local build = {}
                for key, value in pairs(entry) do
                    build[key] = value
                end
                build.version = version
                return build
            end
        end
        error("PHP version not found: " .. version)
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
