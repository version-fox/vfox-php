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

local http = require("http")
local util = require("util")

--- Extension point, called after PreInstall, can perform additional operations,
--- such as file operations for the SDK installation directory or compile source code
--- Currently can be left unimplemented!
function PLUGIN:PostInstall(ctx)
    local sdkInfo = ctx.sdkInfo["php"]
    local path = sdkInfo.path
    if RUNTIME.osType == "windows" then
        InstallComposerForWin(path)
    else
        CompileInstallPHP(path, sdkInfo.version)
    end
end

-- Returns the body of url, or fails with the reason. A failed or partial
-- download must stop the install, not be written out as an installer.
local function fetch_or_fail(url)
    local resp, err = http.get({ url = url })
    if err ~= nil or resp == nil then
        error("Failed to download " .. url .. ": " .. tostring(err or "no response"))
    end
    if resp.status_code ~= 200 then
        error("Failed to download " .. url .. ": HTTP " .. tostring(resp.status_code))
    end
    return resp.body
end

-- The builds load the Visual C++ runtime, which the plugin does not install.
-- Without it php.exe exits at once. Every check below runs php.exe, so this one
-- runs first: the install then names the runtime, rather than reporting an
-- installer that does not match.
local function check_php_starts(path)
    local startBat = path .. "\\php_start.bat"
    local _, err = util.write_file(startBat, '"' .. path .. '\\php.exe" -n -r "exit(0);"')
    if err ~= nil then
        error(err)
    end
    local started = os.execute('""' .. startBat .. '""')
    os.remove(startBat)
    if started ~= 0 then
        local redist = RUNTIME.archType == "386" and "x86" or "x64"
        error(
            string.format(
                "php.exe did not start (exit code %s). The PHP builds for Windows load the Microsoft Visual C++ 2015-2022 Redistributable, which the plugin does not install. Install the %s build from https://aka.ms/vs/17/release/vc_redist.%s.exe, then install PHP again. Composer was not installed.",
                tostring(started),
                redist,
                redist
            )
        )
    end
end

function InstallComposerForWin(path)
    check_php_starts(path)
    local content, err = util.read_file(path .. "\\php.ini-development")
    if err ~= nil then
        error(err)
    end
    -- Use an absolute extension_dir so php.exe can locate php_openssl.dll
    -- regardless of which CWD it was launched from. The composer-setup
    -- step below invokes php.exe from the user's shell CWD, so a relative
    -- "./ext" path resolves to the wrong directory and fails to load
    -- openssl, breaking the HTTPS download Composer needs.
    local ext_dir = (path .. "\\ext"):gsub("\\", "/")
    content = content:gsub(';%s*extension_dir = "ext"', function()
        return 'extension_dir = "' .. ext_dir .. '"'
    end)
    content = content:gsub(";extension=openssl", "extension=openssl")
    content = content:gsub(";extension=php_openssl.dll", "extension=php_openssl.dll")
    _, err = util.write_file(path .. "\\php.ini", content)
    if err ~= nil then
        error(err)
    end

    local installer = fetch_or_fail("https://getcomposer.org/installer")
    -- The sha384 that Composer publishes, as bin/install checks it on Linux and macOS.
    local expected = (fetch_or_fail("https://composer.github.io/installer.sig"):gsub("%s", ""))
    local setup = path .. "\\composer-setup.php"
    _, err = util.write_file(setup, installer)
    if err ~= nil then
        error(err)
    end

    -- Paths that hold spaces must be quoted, and a command line that starts with
    -- a quoted path has to be wrapped in one more pair of quotes for cmd.exe.
    local phpPath = '"' .. path .. '\\php.exe"'
    local setupPath = '"' .. setup .. '"'
    local installPath = '"' .. path .. '"'

    -- PHP computes the hash, so no crypto library is needed in Lua.
    local verifyBat = path .. "\\composer_verify.bat"
    _, err = util.write_file(
        verifyBat,
        phpPath .. " -r \"if (hash_file('sha384', '" .. setup .. "') === '" .. expected .. "') { exit(0); } exit(1);\""
    )
    if err ~= nil then
        error(err)
    end
    local verified = os.execute('""' .. verifyBat .. '""')
    os.remove(verifyBat)
    if verified ~= 0 then
        os.remove(setup)
        error("The Composer installer does not match the sha384 that Composer publishes; Composer was not installed.")
    end

    local installBat = path .. "\\composer_install.bat"
    _, err = util.write_file(installBat, phpPath .. " " .. setupPath .. " --install-dir=" .. installPath)
    if err ~= nil then
        error(err)
    end
    local code = os.execute('""' .. installBat .. '""')
    os.remove(installBat)
    os.remove(setup)
    if code ~= 0 then
        error("Failed to install composer.")
    end

    util.write_file(path .. "\\composer.bat", '@php "%~dp0composer.phar" %*')
end

function CompileInstallPHP(path, version)
    if not version:match("^%d+%.%d+%.%d+$") then
        error("Invalid PHP source version: " .. tostring(version))
    end
    local install = RUNTIME.pluginDirPath .. "/bin/install"
    os.execute('chmod +x "' .. install .. '"')
    local code = os.execute('"' .. install .. '" "' .. path .. '" ' .. version)
    if code ~= 0 then
        error("Compilation Failure.")
    end
end
