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
-- registered says whether the registry records the runtime. The batch files report
-- the exit statuses the test sets: php.exe starts with start_exit, or with
-- start_after_redist once the runtime's installer has run.
local S = {}

-- Every test starts from a clean state.
local function reset(overrides)
    for key in pairs(S) do
        S[key] = nil
    end
    S.files = {}
    S.binary = {}
    S.commands = {}
    S.queries = {}
    S.removed = {}
    S.urls = {}
    S.registered = true
    S.verify_exit = 0
    S.start_exit = 0
    S.start_after_redist = 0
    S.redist_exit = 0
    S.redist_ran = false
    S.redist_resp = { status_code = 200, body = "MZ\r\n\0" }
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
-- The runtime's installer is written as bytes, never through the text writer.
util.write_binary_file = function(path, content)
    S.binary[path] = content
    return true
end
-- The registry query prints the Installed value when the runtime is recorded.
io.popen = function(command)
    S.queries[#S.queries + 1] = command
    local output = S.registered and "    Installed    REG_DWORD    0x1\r\n" or ""
    return {
        read = function()
            return output
        end,
        close = function() end,
    }
end
package.preload.http = function()
    return {
        get = function(args)
            S.urls[#S.urls + 1] = args.url
            if args.url == "https://composer.github.io/installer.sig" then
                return S.sig
            end
            if args.url:find("^https://aka%.ms/") then
                return S.redist_resp
            end
            return { status_code = 200, body = "composer installer" }
        end,
    }
end
os.execute = function(command)
    S.commands[#S.commands + 1] = command
    if command:find("php_start.bat", 1, true) then
        if S.redist_ran then
            return S.start_after_redist
        end
        return S.start_exit
    end
    if command:find("install_vc_redist.bat", 1, true) then
        S.redist_ran = true
        return S.redist_exit
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

-- Returns the message of the failure that fn raises.
local function error_of(fn)
    local ok, err = pcall(fn)
    assert(not ok, "the install must fail")
    return tostring(err)
end

local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end
    return false
end

local path = "C:\\SDKs\\100% PHP"
local installer = path .. "\\vc_redist.x64.exe"
local redist_url = "https://aka.ms/vs/17/release/vc_redist.x64.exe"

-- A successful install with the runtime recorded: the registry says so, php.exe starts,
-- then the php.ini, both downloads, the check, and the install.
post_install(path)
assert(#S.queries == 1 and S.queries[1]:find("VisualStudio\\14.0\\VC\\Runtimes\\X64", 1, true), S.queries[1])
local ini = assert(S.files[path .. "\\php.ini"])
assert(ini:find('extension_dir = "C:/SDKs/100% PHP/ext"', 1, true), ini)
assert(ini:find("\nextension=openssl\n", 1, true), ini)
assert(ini:find("\nextension=php_openssl.dll\n", 1, true), ini)
assert(#S.urls == 2, "the runtime is not downloaded when it is recorded")
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

-- The runtime is not recorded: it is downloaded from Microsoft, written as bytes, and
-- installed by the helper. Then php.exe starts, and the install carries on.
reset({ registered = false })
post_install(path)
assert(S.urls[1] == redist_url, S.urls[1])
assert(S.binary[installer] == "MZ\r\n\0", "the installer must be written as its bytes")
assert(S.files[installer] == nil, "the installer must not go through the text writer")
local helper = assert(S.files[path .. "\\install_vc_redist.ps1"])
assert(helper:find("Get-AuthenticodeSignature", 1, true), helper)
assert(helper:find("O=Microsoft Corporation", 1, true), helper)
assert(helper:find("trap { exit 102 }", 1, true), helper)
local run = assert(S.files[path .. "\\install_vc_redist.bat"])
assert(run:find('-File "' .. path .. '\\install_vc_redist.ps1" -Installer "' .. installer .. '"', 1, true), run)
-- PowerShell 7 puts its modules on PSModulePath, so the batch file gives Windows PowerShell
-- its own module path, and runs it by its full path.
assert(run:find('@set "PSModulePath=%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\Modules"', 1, true), run)
assert(run:find('"%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NoProfile', 1, true), run)
-- php.exe is not run before the installer: the installer runs, php.exe is checked, then
-- the composer steps.
assert(#S.commands == 4, #S.commands)
assert(S.commands[1]:find("install_vc_redist.bat", 1, true), S.commands[1])
assert(S.commands[2]:find("php_start.bat", 1, true), S.commands[2])
assert(S.files[path .. "\\php.ini"] ~= nil, "php.ini is written once php.exe starts")
for _, file in ipairs({ installer, path .. "\\install_vc_redist.ps1", path .. "\\install_vc_redist.bat" }) do
    assert(contains(S.removed, file), "the runtime's files are removed: " .. file)
end
print("Windows installs the runtime when it is not recorded, then carries on")

-- The runtime is recorded, but php.exe does not start: nothing is downloaded, and the
-- install says what to repair.
reset({ start_exit = 1 })
local message = error_of(function()
    post_install(path)
end)
assert(message:find("php.exe does not start", 1, true), message)
assert(message:find("repair the Redistributable from Apps & Features", 1, true), message)
assert(#S.urls == 0, "nothing may be downloaded when the runtime is recorded")
assert(#S.commands == 1, "only the start check may run")
assert(S.files[path .. "\\php.ini"] == nil, "nothing may be written when php.exe does not start")
print("Windows reports a recorded runtime that php.exe cannot use, with the repair to make")

-- A runtime that cannot be downloaded stops the install before anything else is written.
reset({ registered = false, redist_resp = { status_code = 503, body = "" } })
message = error_of(function()
    post_install(path)
end)
assert(message:find("is not installed, and it could not be downloaded from " .. redist_url, 1, true), message)
assert(message:find("Install the x64 build from " .. redist_url .. " yourself", 1, true), message)
assert(#S.commands == 0, "php.exe is not run when the runtime is missing")
assert(S.binary[installer] == nil, "no installer may be written when the download fails")
assert(S.files[path .. "\\php.ini"] == nil, "nothing may be written when the download fails")
print("Windows reports a runtime that cannot be downloaded, with the link to install it")

-- An installer that Microsoft did not sign is not run, and it is removed.
reset({ registered = false, redist_exit = 100 })
message = error_of(function()
    post_install(path)
end)
assert(message:find("is not signed by Microsoft, so it was not run", 1, true), message)
assert(#S.commands == 1, "php.exe is not checked after an installer that did not run")
assert(contains(S.removed, installer), "the unsigned installer is removed")
assert(S.files[path .. "\\php.ini"] == nil, "nothing may be written for an unsigned installer")
print("Windows does not run a runtime installer that Microsoft did not sign")

-- When Windows does not start the installer, the install says so and gives the link.
reset({ registered = false, redist_exit = 101 })
message = error_of(function()
    post_install(path)
end)
assert(message:find("Windows did not start the Visual C++ Redistributable installer", 1, true), message)
assert(message:find(redist_url, 1, true), message)
assert(S.files[path .. "\\php.ini"] == nil, "nothing may be written when the installer did not start")
print("Windows reports an installer that it did not start")

-- When PowerShell itself fails, the install says so, rather than naming an installer code.
reset({ registered = false, redist_exit = 102 })
message = error_of(function()
    post_install(path)
end)
assert(message:find("PowerShell could not check or start the Visual C++ Redistributable installer", 1, true), message)
assert(message:find(redist_url, 1, true), message)
assert(S.files[path .. "\\php.ini"] == nil, "nothing may be written when PowerShell fails")
print("Windows reports a PowerShell failure apart from the installer's exit code")

-- Any other exit code of the installer fails the install with that code.
reset({ registered = false, redist_exit = 1603 })
message = error_of(function()
    post_install(path)
end)
assert(message:find("installer exited with code 1603", 1, true), message)
assert(message:find(redist_url, 1, true), message)
assert(S.files[path .. "\\php.ini"] == nil, "nothing may be written when the installer fails")
print("Windows reports a runtime installer that fails")

-- Exit 3010 means the runtime is installed and a restart is pending: php.exe is checked again.
reset({ registered = false, redist_exit = 3010, start_after_redist = 0 })
post_install(path)
assert(S.files[path .. "\\php.ini"] ~= nil, "php.ini is written when php.exe starts after a restart is pending")
print("Windows accepts a runtime install that asks for a restart")

-- php.exe still does not start after the installer ran: the install stops before php.ini.
reset({ registered = false, redist_exit = 0, start_after_redist = 1 })
message = error_of(function()
    post_install(path)
end)
assert(message:find("php.exe does not start", 1, true), message)
assert(#S.commands == 2, "php.exe is checked once, after the installer")
assert(S.files[path .. "\\php.ini"] == nil, "nothing may be written while php.exe does not start")
print("Windows stops when php.exe still does not start after the runtime install")

-- An x86 PHP needs the x86 Redistributable, and the x86 record of the registry.
RUNTIME.archType = "386"
reset({ registered = false })
post_install(path)
assert(S.queries[1]:find("VisualStudio\\14.0\\VC\\Runtimes\\X86", 1, true), S.queries[1])
assert(S.urls[1] == "https://aka.ms/vs/17/release/vc_redist.x86.exe", S.urls[1])
assert(S.binary[path .. "\\vc_redist.x86.exe"] ~= nil, "the x86 installer is the one written")
RUNTIME.archType = nil
print("Windows installs the x86 Redistributable for x86 builds")
