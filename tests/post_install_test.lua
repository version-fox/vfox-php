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

-- The Linux and macOS compile step of the PostInstall hook: what it asks the build for,
-- and the versions it refuses before anything is built. The build itself is tested in
-- php_build_test.lua, and the Windows steps in windows_test.lua.
package.path = "./lib/?.lua;" .. package.path
PLUGIN = {}
RUNTIME = { osType = "linux", pluginDirPath = "/plugins/php" }

-- The fakes and the test share one table, and only its fields change: the Lua runtime used
-- here does not see a local that the test rebinds, as windows_test.lua notes.
local S = { calls = {}, fail_with = nil }

-- The Windows steps of the hook use http, which the Linux compile step never calls.
package.preload.http = function()
    return {
        get = function()
            error("the Linux compile step downloads nothing from the hook")
        end,
    }
end
package.preload.php_build = function()
    return {
        install = function(path, version, zts)
            table.insert(S.calls, { path = path, version = version, zts = zts })
            if S.fail_with then
                error(S.fail_with, 0)
            end
        end,
    }
end
dofile("hooks/post_install.lua")

local function post_install(path, version)
    PLUGIN:PostInstall({ sdkInfo = { php = { path = path, version = version } } })
end

-- A release is built into its install path.
post_install("/home/user/.vfox/sdks/php-8.5.12", "8.5.12")
assert(#S.calls == 1, "the build runs once")
assert(S.calls[1].path == "/home/user/.vfox/sdks/php-8.5.12", S.calls[1].path)
assert(S.calls[1].version == "8.5.12" and S.calls[1].zts == false, S.calls[1].version)
print("Linux compile builds the release into its install path")

-- A path with spaces is passed on whole: the build links it to a directory without spaces.
S.calls = {}
post_install("/home/John Doe/.vfox/sdks/php-8.5.12", "8.5.12")
assert(S.calls[1].path == "/home/John Doe/.vfox/sdks/php-8.5.12", S.calls[1].path)
print("Linux compile passes an install path with spaces on whole")

-- A ZTS build is named with -zts: the build gets the release and the ZTS flag.
S.calls = {}
post_install("/home/user/.vfox/sdks/php-8.4.5-zts", "8.4.5-zts")
assert(S.calls[1].version == "8.4.5" and S.calls[1].zts == true, S.calls[1].version)
print("Linux compile builds a ZTS release with its flag")

-- A version that is not a full release is refused before anything is built.
S.calls = {}
local ok, err = pcall(post_install, "/x", "8.4-zts")
assert(not ok and tostring(err):find("Invalid PHP source version: 8.4-zts", 1, true), tostring(err))
ok, err = pcall(post_install, "/x", "8.5")
assert(not ok and tostring(err):find("Invalid PHP source version", 1, true), tostring(err))
assert(#S.calls == 0, "nothing is built for a version that is refused")
print("Linux compile refuses a version that is not x.y.z")

-- A build that fails is reported to vfox.
S.calls = {}
S.fail_with = "Compilation Failure: make did not succeed."
ok, err = pcall(post_install, "/x", "8.5.12")
assert(not ok and tostring(err):find("Compilation Failure", 1, true), tostring(err))
print("Linux compile reports a failed build")
