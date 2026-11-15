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

-- The PreUninstall hook: on Linux and macOS it asks bin/install to remove the
-- build behind the main SDK's install path, and on Windows it runs nothing. vfox
-- passes the install path as ctx.main.path.
package.path = "./lib/?.lua;" .. package.path
PLUGIN = {}
RUNTIME = { osType = "linux", pluginDirPath = "/plugins/php" }

local S = { commands = {}, exit_status = 0 }
os.execute = function(command)
    S.commands[#S.commands + 1] = command
    return S.exit_status
end
dofile("hooks/pre_uninstall.lua")

local path = "/home/John Doe/.vfox/cache/php/v-8.5.12/php-8.5.12"
PLUGIN:PreUninstall({ main = { path = path, version = "8.5.12" } })
assert(S.commands[1] == 'chmod +x "/plugins/php/bin/install"', S.commands[1])
assert(S.commands[2] == '"/plugins/php/bin/install" --remove-build "' .. path .. '"', S.commands[2])
print("Linux uninstall asks bin/install to remove the build of the install path")

-- A context without an install path leaves nothing to remove, and the uninstall
-- goes on: the hook does not fail it.
S.commands = {}
PLUGIN:PreUninstall({ sdkInfo = {} })
assert(#S.commands == 0, "nothing may run without an install path")
print("Linux uninstall does nothing without an install path")

-- The install path can also come from sdkInfo, as PostInstall reads it.
S.commands = {}
PLUGIN:PreUninstall({ sdkInfo = { php = { path = "/y z" } } })
assert(S.commands[2] == '"/plugins/php/bin/install" --remove-build "/y z"', S.commands[2])
print("Linux uninstall finds the install path in sdkInfo")

-- A removal that fails is reported, not ignored.
S.commands = {}
S.exit_status = 1
local ok, err = pcall(PLUGIN.PreUninstall, PLUGIN, { main = { path = "/x" } })
assert(not ok and tostring(err):find("Failed to remove the PHP build behind /x", 1, true), tostring(err))
print("Linux uninstall reports a removal that fails")

-- On Windows nothing runs: the Windows builds are unpacked, not compiled.
RUNTIME.osType = "windows"
S.commands = {}
S.exit_status = 0
PLUGIN:PreUninstall({ main = { path = "C:\\x" } })
assert(#S.commands == 0, "nothing may run on Windows")
print("Windows uninstall runs nothing")
