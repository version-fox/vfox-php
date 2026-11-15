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
RUNTIME = { osType = "windows" }
local util = require("util")

-- The fakes and the test share one table, and only its fields change: the
-- Lua runtime used here does not see a local that a function has rebound.
local S = {}

-- Every test starts from a clean state. os.execute reports the exit status
-- that the test chooses for the verification batch file.
local function reset(overrides)
    for key in pairs(S) do
        S[key] = nil
    end
    S.files = {}
    S.commands = {}
    S.removed = {}
    S.urls = {}
    S.verify_exit = 0
    S.sig = { status_code = 200, body = "  ABCDEF\n" }
    for key, value in pairs(overrides or {}) do
        S[key] = value
    end
end
reset()

util.read_file = function()
    return ';extension_dir = "ext"\n;extension=openssl\n;extension=php_openssl.dll\n'
end
util.write_file = function(path, content)
    S.files[path] = content
    return true
end
package.preload.http = function()
    return {
        get = function(args)
            S.urls[#S.urls + 1] = args.url
            if args.url == "https://composer.github.io/installer.sig" then
                return S.sig
            end
            return { status_code = 200, body = "composer installer" }
        end,
    }
end
os.execute = function(command)
    S.commands[#S.commands + 1] = command
    if command:find("composer_verify.bat", 1, true) then
        return S.verify_exit
    end
    return 0
end
os.remove = function(path)
    S.removed[#S.removed + 1] = path
end
dofile("hooks/post_install.lua")

local function post_install(path)
    PLUGIN:PostInstall({ sdkInfo = { php = { path = path, version = "8.4.2" } } })
end

local function fails(fn, expected)
    local ok, err = pcall(fn)
    assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
end

-- A successful install: the php.ini, both downloads, the check, then the install.
local path = "C:\\SDKs\\100% PHP"
post_install(path)
local ini = assert(S.files[path .. "\\php.ini"])
assert(ini:find('extension_dir = "C:/SDKs/100% PHP/ext"', 1, true), ini)
assert(ini:find("\nextension=openssl\n", 1, true), ini)
assert(ini:find("\nextension=php_openssl.dll\n", 1, true), ini)
assert(S.urls[1] == "https://getcomposer.org/installer", S.urls[1])
assert(S.urls[2] == "https://composer.github.io/installer.sig", S.urls[2])
-- The signature is trimmed, and PHP compares it with the installer's sha384.
local verify = assert(S.files[path .. "\\composer_verify.bat"])
assert(verify:find("=== 'ABCDEF'", 1, true), verify)
assert(verify:find(path .. "\\composer-setup.php", 1, true), verify)
-- Both batch files run quoted, so a path with spaces stays one argument for cmd.exe.
assert(#S.commands == 2, #S.commands)
assert(S.commands[1] == '""' .. path .. '\\composer_verify.bat""', S.commands[1])
assert(S.commands[2] == '""' .. path .. '\\composer_install.bat""', S.commands[2])
local install = assert(S.files[path .. "\\composer_install.bat"])
assert(install:find('--install-dir="C:\\SDKs\\100% PHP"', 1, true), install)
print("Windows PHP extension path substitution and composer install passed")

-- An installer that does not match the published sha384 is never installed.
reset({ verify_exit = 1 })
fails(function()
    post_install(path)
end, "does not match the sha384")
assert(#S.commands == 1, "the installer must not run after a failed check")
assert(S.removed[#S.removed] == path .. "\\composer-setup.php", S.removed[#S.removed])
print("Windows composer installer verification refuses a mismatch")

-- Without the published signature there is nothing to check against: stop.
reset({ sig = { status_code = 503, body = "" } })
fails(function()
    post_install(path)
end, "HTTP 503")
assert(#S.commands == 0, "no install step may run without the signature")
print("Windows composer installer stops when the signature cannot be fetched")
