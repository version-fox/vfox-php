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
-- The start and verification batch files report the exit statuses the test sets.
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
    S.start_exit = 0
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
    if command:find("php_start.bat", 1, true) then
        return S.start_exit
    end
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
-- Every batch file runs quoted, so a path with spaces stays one argument for cmd.exe.
assert(#S.commands == 3, #S.commands)
assert(S.commands[1] == '""' .. path .. '\\php_start.bat""', S.commands[1])
assert(S.commands[2] == '""' .. path .. '\\composer_verify.bat""', S.commands[2])
assert(S.commands[3] == '""' .. path .. '\\composer_install.bat""', S.commands[3])
local start = assert(S.files[path .. "\\php_start.bat"])
assert(start:find('"' .. path .. '\\php.exe" -n -r "exit(0);"', 1, true), start)
local install = assert(S.files[path .. "\\composer_install.bat"])
assert(install:find('--install-dir="C:\\SDKs\\100% PHP"', 1, true), install)
print("Windows PHP extension path substitution and composer install passed")

-- An installer that does not match the published sha384 is never installed.
reset({ verify_exit = 1 })
fails(function()
    post_install(path)
end, "does not match the sha384")
assert(#S.commands == 2, "the installer must not run after a failed check")
assert(S.removed[#S.removed] == path .. "\\composer-setup.php", S.removed[#S.removed])
print("Windows composer installer verification refuses a mismatch")

-- Without the published signature there is nothing to check against: stop.
reset({ sig = { status_code = 503, body = "" } })
fails(function()
    post_install(path)
end, "HTTP 503")
assert(
    #S.commands == 1 and S.commands[1]:find("php_start.bat", 1, true),
    "only the start check may run before the signature"
)
print("Windows composer installer stops when the signature cannot be fetched")

-- A php.exe that does not start is the missing runtime, not a Composer mismatch.
-- It is found before anything is written or downloaded.
reset({ start_exit = -1073741515 })
local ok, err = pcall(post_install, path)
assert(not ok, "a php.exe that does not start must fail the install")
assert(tostring(err):find("php.exe did not start (exit code -1073741515)", 1, true), tostring(err))
assert(tostring(err):find("https://aka.ms/vs/17/release/vc_redist.x64.exe", 1, true), tostring(err))
assert(not tostring(err):find("sha384", 1, true), tostring(err))
assert(#S.commands == 1, "only the start check may run")
assert(#S.urls == 0, "nothing may be downloaded when php.exe does not start")
assert(S.files[path .. "\\php.ini"] == nil, "nothing may be written when php.exe does not start")
print("Windows reports a php.exe that does not start as the missing runtime")

-- An x86 PHP needs the x86 Redistributable.
RUNTIME.archType = "386"
reset({ start_exit = 1 })
ok, err = pcall(post_install, path)
assert(not ok and tostring(err):find("vc_redist.x86.exe", 1, true), tostring(err))
RUNTIME.archType = nil
print("Windows names the x86 Redistributable for x86 builds")
