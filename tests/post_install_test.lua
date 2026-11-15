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

-- The Linux and macOS compile step: the commands it runs, the install paths it
-- passes on, and the failures it reports. The Windows steps are in windows_test.lua.
package.path = "./lib/?.lua;" .. package.path
PLUGIN = {}
RUNTIME = { osType = "linux", pluginDirPath = "/plugins/php" }
package.preload.http = function()
    return {
        get = function()
            error("the Linux compile step downloads nothing")
        end,
    }
end

-- The fakes and the test share one table, and only its fields change: the
-- Lua runtime used here does not see a local that a function has rebound.
local S = { commands = {}, exit_status = 0 }
os.execute = function(command)
    S.commands[#S.commands + 1] = command
    return S.exit_status
end
dofile("hooks/post_install.lua")

local function post_install(path, version)
    PLUGIN:PostInstall({ sdkInfo = { php = { path = path, version = version } } })
end

-- A path without spaces: the script and the path are quoted.
post_install("/home/user/.vfox/sdks/php-8.5.12", "8.5.12")
assert(S.commands[1] == 'chmod +x "/plugins/php/bin/install"', S.commands[1])
assert(S.commands[2] == '"/plugins/php/bin/install" "/home/user/.vfox/sdks/php-8.5.12" 8.5.12', S.commands[2])
print("Linux compile quotes the install path")

-- A path with spaces is passed on whole, quoted. bin/install builds PHP in a
-- directory without spaces and links the path to it, so the hook does not refuse it.
S.commands = {}
post_install("/home/John Doe/.vfox/sdks/php-8.5.12", "8.5.12")
assert(S.commands[2] == '"/plugins/php/bin/install" "/home/John Doe/.vfox/sdks/php-8.5.12" 8.5.12', S.commands[2])
print("Linux compile passes an install path with spaces on whole")

-- A ZTS build passes --zts before the install path, and bin/install gets the release.
S.commands = {}
post_install("/home/user/.vfox/sdks/php-8.4.5-zts", "8.4.5-zts")
assert(S.commands[2] == '"/plugins/php/bin/install" --zts "/home/user/.vfox/sdks/php-8.4.5-zts" 8.4.5', S.commands[2])
print("Linux compile builds a ZTS PHP with --zts")

-- A ZTS name that is not a full release is refused before anything runs.
S.commands = {}
local ok, err = pcall(post_install, "/x", "8.4-zts")
assert(not ok and tostring(err):find("Invalid PHP source version: 8.4-zts", 1, true), tostring(err))
assert(#S.commands == 0, "nothing may run for a ZTS name that is refused")

-- A version that is not x.y.z is refused before anything runs.
S.commands = {}
ok, err = pcall(post_install, "/x", "8.5")
assert(not ok and tostring(err):find("Invalid PHP source version", 1, true), tostring(err))
assert(#S.commands == 0, "nothing may run for a version that is refused")
print("Linux compile refuses a version that is not x.y.z")

-- A compile that exits non-zero is reported, not ignored.
S.commands = {}
S.exit_status = 2
ok, err = pcall(post_install, "/x", "8.5.12")
assert(not ok and tostring(err):find("Compilation Failure.", 1, true), tostring(err))
print("Linux compile reports a failed build")
