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

-- The PreUninstall hook: on Linux and macOS it asks lib/php_build.lua to remove the build
-- behind the main SDK's install path, and on Windows it does nothing. vfox passes the install
-- path as ctx.main.path.
package.path = "./lib/?.lua;" .. package.path
PLUGIN = {}
RUNTIME = { osType = "linux", pluginDirPath = "/plugins/php" }

local removed = {}
local fail_with = nil
package.preload.php_build = function()
    return {
        remove_build = function(path)
            table.insert(removed, path)
            if fail_with then
                error(fail_with, 0)
            end
        end,
    }
end
dofile("hooks/pre_uninstall.lua")

local path = "/home/John Doe/.vfox/cache/php/v-8.5.12/php-8.5.12"
PLUGIN:PreUninstall({ main = { path = path, version = "8.5.12" } })
assert(#removed == 1 and removed[1] == path, removed[1])
print("Linux uninstall removes the build of the install path")

-- A context without an install path leaves nothing to remove, and the uninstall goes on.
removed = {}
PLUGIN:PreUninstall({ sdkInfo = {} })
assert(#removed == 0, "nothing may be removed without an install path")
print("Linux uninstall does nothing without an install path")

-- The install path can also come from sdkInfo, as PostInstall reads it.
removed = {}
PLUGIN:PreUninstall({ sdkInfo = { php = { path = "/y z" } } })
assert(#removed == 1 and removed[1] == "/y z", removed[1])
print("Linux uninstall finds the install path in sdkInfo")

-- A removal that fails is reported with the install path and the reason.
removed = {}
fail_with = "ERROR: /x links to /tmp, which is not a vfox-php build directory"
local ok, err = pcall(PLUGIN.PreUninstall, PLUGIN, { main = { path = "/x" } })
assert(not ok, "a removal that fails must fail the uninstall")
assert(tostring(err):find("Failed to remove the PHP build behind /x", 1, true), tostring(err))
assert(tostring(err):find("is not a vfox-php build directory", 1, true), tostring(err))
fail_with = nil
print("Linux uninstall reports a removal that fails")

-- On Windows nothing runs: the Windows builds are unpacked, not compiled.
RUNTIME.osType = "windows"
removed = {}
PLUGIN:PreUninstall({ main = { path = "C:\\x" } })
assert(#removed == 0, "nothing may be removed on Windows")
print("Windows uninstall runs nothing")
