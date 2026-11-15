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

package.path = "./lib/?.lua;" .. package.path
PLUGIN = {}
RUNTIME = { osType = "windows", archType = "amd64" }
local responses, state = {}, {}
package.preload.http = function()
    return {
        get = function(args)
            if state.failure then
                return state.failure.response, state.failure.error
            end
            return { status_code = 200, body = assert(responses[args.url], "unexpected URL " .. args.url) }
        end,
    }
end
package.preload.json = function()
    return {
        decode = function(body)
            return body
        end,
    }
end
package.preload.html = function()
    return {
        parse = function(body)
            return {
                find = function()
                    return {
                        each = function(_, fn)
                            for i, filename in ipairs(body) do
                                fn(i, {
                                    attr = function()
                                        return filename
                                    end,
                                    text = function()
                                        return filename
                                    end,
                                })
                            end
                        end,
                    }
                end,
            }
        end,
    }
end
local current = "https://windows.php.net/downloads/releases/"
local archives = current .. "archives/"
responses[current] = {
    "/downloads/releases/php-8.4.2-nts-Win32-vs17-x64.zip",
    "/downloads/releases/php-8.4.2-Win32-vs17-x64.zip",
    "/downloads/releases/php-8.4.2-Win32-vs17-x86.zip",
    "/downloads/releases/php-8.4.2-debug-pack-Win32-vs17-x64.zip",
}
responses[archives] = {
    "php-5.6.16-nts-Win32-VC11-x64.zip",
    "php-8.4.2-Win32-vs17-x64.zip",
    "php-8.3.15-Win32-vs16-x64.zip",
    "php-8.4.1-nts-Win32-vs17-x64.zip",
    "php-8.2.35-1-nts-Win32-vs16-x64.zip",
    "php-7.2.33-1-Win32-VC15-x64.zip",
    "php-7.2.33-Win32-VC15-x64.zip",
}
for _, major in ipairs({ 5, 7, 8 }) do
    responses["https://www.php.net/releases/index.php?json&max=10000&version=" .. major] = {}
end
responses["https://www.php.net/releases/index.php?json&max=10000&version=8"] = {
    ["8.4.2"] = { source = { { filename = "php-8.4.2.tar.gz", sha256 = string.rep("a", 64) } } },
    ["8.3.15"] = { source = { { filename = "php-8.3.15.tar.gz", sha256 = string.rep("b", 64) } } },
    ["8.5.0RC1"] = { source = { { filename = "php-8.5.0RC1.tar.gz" } } },
}
dofile("hooks/available.lua")
dofile("hooks/pre_install.lua")
local list = PLUGIN:Available({})
assert(list[1].version == "8.4.2", "latest must be current TS, got " .. tostring(list[1].version))
assert(#list == 7, #list)
assert(PLUGIN:PreInstall({ version = "7.2.33" }).url == archives .. "php-7.2.33-1-Win32-VC15-x64.zip")
assert(PLUGIN:PreInstall({ version = "latest" }).url == current .. "php-8.4.2-Win32-vs17-x64.zip")
assert(PLUGIN:PreInstall({ version = "8.4.2-nts" }).version == "8.4.2-nts")
-- Windows has no -zts build: the plain version is the TS build, so -zts names nothing.
local zts_ok, zts_err = pcall(PLUGIN.PreInstall, PLUGIN, { version = "8.4.2-zts" })
assert(not zts_ok and tostring(zts_err):find("not found", 1, true), tostring(zts_err))
-- NTS builds carry the rebuild number before "nts", as the release listing names them.
assert(PLUGIN:PreInstall({ version = "8.2.35-nts" }).url == archives .. "php-8.2.35-1-nts-Win32-vs16-x64.zip")
assert(PLUGIN:PreInstall({ version = "8.3" }).url == archives .. "php-8.3.15-Win32-vs16-x64.zip")
RUNTIME.archType = "386"
assert(#PLUGIN:Available({}) == 1)
RUNTIME.osType = "linux"
list = PLUGIN:Available({})
assert(#list == 2 and list[1].version == "8.4.2")
local install = PLUGIN:PreInstall({ version = "8.4" })
assert(install.url == "https://www.php.net/distributions/php-8.4.2.tar.gz")
assert(install.sha256 == string.rep("a", 64))
-- On Linux and macOS, -zts is the source of the release, installed as a ZTS build.
local zts = PLUGIN:PreInstall({ version = "8.4.2-zts" })
assert(zts.version == "8.4.2-zts", zts.version)
assert(zts.url == install.url and zts.sha256 == install.sha256, zts.url)
-- The ZTS entry is a copy: the release in the list keeps its plain name.
assert(PLUGIN:PreInstall({ version = "8.4" }).version == "8.4.2")
local function fails(fn, expected)
    local ok, err = pcall(fn)
    assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
end
-- -zts takes a full release, as -nts does, and only a release the list has.
fails(function()
    PLUGIN:PreInstall({ version = "8.4-zts" })
end, "PHP version not found: 8.4-zts")
fails(function()
    PLUGIN:PreInstall({ version = "9.0.0-zts" })
end, "PHP version not found: 9.0.0-zts")
state.failure = { error = "timeout" }
fails(function()
    PLUGIN:Available({})
end, "timeout")
state.failure = { response = { status_code = 503 } }
fails(function()
    PLUGIN:PreInstall({ version = "latest" })
end, "503")
state.failure = nil
fails(function()
    PLUGIN:PreInstall({ version = "99.0.0" })
end, "not found")
-- vfox use: a line or a major takes the newest installed build of the default type,
-- its plain name. A name with -zts or -nts is taken as it is, and a version that is
-- not installed is returned as typed, never replaced by a build of another type.
dofile("hooks/pre_use.lua")
local function use(version, names)
    local sdks = {}
    for _, name in ipairs(names) do
        sdks[name] = { name = "php", version = name, path = "/opt/php/" .. name }
    end
    local result = PLUGIN:PreUse({ version = version, installedSdks = sdks })
    return result and result.version
end
local linux = { "8.4.4", "8.4.5", "8.4.5-zts", "8.4.6-zts" }
assert(use("8.4", linux) == "8.4.5", "8.4 takes the newest plain build, not 8.4.6-zts")
assert(use("8", linux) == "8.4.5", "8 takes the newest plain build too")
assert(use("8.4.5", linux) == "8.4.5")
assert(use("8.4.5-zts", linux) == "8.4.5-zts")
assert(use("8.4.6-zts", linux) == "8.4.6-zts")
assert(use("8.4.6", linux) == "8.4.6", "8.4.6 is not installed, and is not taken from 8.4.6-zts")
assert(use("8.5", linux) == "8.5", "8.5 is not installed, and is not taken from another build")
assert(use("8.4-zts", linux) == "8.4-zts", "a line with a suffix is not a version")
local windows = { "8.4.4", "8.4.5", "8.4.5-nts" }
assert(use("8.4", windows) == "8.4.5", "a line takes the TS build, not the NTS one")
assert(use("8.4.5-nts", windows) == "8.4.5-nts")
local numeric = { "8.4.9", "8.4.10" }
assert(use("8.4", numeric) == "8.4.10", "the newest patch is the highest number, not the last name")
assert(use("8.4", {}) == "8.4", "nothing installed: the version as typed")
assert(use("", linux) == nil, "no version gives no result, so vfox keeps its own matching")
print("vfox use takes the default build of a line, and never a build of another type")

print("PHP release discovery, ordering, architecture and failure cases passed")
