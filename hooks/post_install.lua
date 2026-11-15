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

function InstallComposerForWin(path)
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

    local resp, err = http.get({
        url = "https://getcomposer.org/installer",
    })
    local setup = path .. "\\composer-setup.php"
    _, err = util.write_file(setup, resp.body)
    if err ~= nil then
        error(err)
    end

    local phpPath = path .. "\\php.exe"
    local setupPath = setup
    local installPath = path
    local execString = phpPath .. " " .. setupPath .. " --install-dir=" .. installPath

    if RUNTIME.osType == "windows" then
        phpPath = '"' .. phpPath .. '"'
        setupPath = '"' .. setupPath .. '"'
        installPath = '"' .. installPath .. '"'

        local winPrefix = ""

        util.write_file(
            path .. "\\composer_install.bat",
            winPrefix .. phpPath .. " " .. setupPath .. " --install-dir=" .. installPath
        )

        execString = path .. "\\composer_install.bat"
    end

    local code = os.execute(execString)
    if code ~= 0 then
        error("Failed to install composer.")
    end

    os.remove(setup)

    if RUNTIME.osType == "windows" then
        os.remove(path .. "\\composer_install.bat")
    end

    util.write_file(path .. "\\composer.bat", '@php "%~dp0composer.phar" %*')
end

function CompileInstallPHP(path, version)
    if not version:match("^%d+%.%d+%.%d+$") then
        error("Invalid PHP source version: " .. tostring(version))
    end
    os.execute("chmod +x " .. RUNTIME.pluginDirPath .. "/bin/install")
    local code = os.execute(RUNTIME.pluginDirPath .. "/bin/install " .. path .. " " .. version)
    if code ~= 0 then
        error("Compilation Failure.")
    end
end
