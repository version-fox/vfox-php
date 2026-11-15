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

--- Called before vfox removes an install, while its link is still in place. On
--- Linux and macOS, an install path that holds a space is a link to a build
--- directory outside it. vfox removes only the link, so the build directory is
--- removed here. The install path is the main SDK's path: ctx.main.path.
function PLUGIN:PreUninstall(ctx)
    if RUNTIME.osType == "windows" then
        return
    end
    local main = ctx.main or (ctx.sdkInfo and ctx.sdkInfo["php"])
    local path = main and main.path
    if path == nil or path == "" then
        -- A vfox that gives no install path leaves nothing to remove here. The
        -- uninstall goes on, as it did before this hook existed.
        return
    end
    local install = RUNTIME.pluginDirPath .. "/bin/install"
    os.execute('chmod +x "' .. install .. '"')
    local code = os.execute('"' .. install .. '" --remove-build "' .. path .. '"')
    if code ~= 0 then
        error("Failed to remove the PHP build behind " .. path)
    end
end
