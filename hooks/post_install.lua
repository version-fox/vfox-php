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

-- Splits the name of an install into its release and whether it is a thread-safe
-- build: "8.4.5-zts" is the ZTS build of 8.4.5. Any other name is returned as it is.
local function split_zts(name)
    local release = name:match("^(%d+%.%d+%.%d+)%-zts$")
    if release then
        return release, true
    end
    return name, false
end

--- Extension point, called after PreInstall, can perform additional operations,
--- such as file operations for the SDK installation directory or compile source code
--- Currently can be left unimplemented!
function PLUGIN:PostInstall(ctx)
    local sdkInfo = ctx.sdkInfo["php"]
    local path = sdkInfo.path
    if RUNTIME.osType == "windows" then
        InstallComposerForWin(path)
    else
        local release, zts = split_zts(sdkInfo.version)
        CompileInstallPHP(path, release, zts)
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

-- The Redistributable records the runtime under this key, with Installed set to 0x1.
-- A 32-bit build reads the x86 record through the 32-bit view of the registry.
local function redist_installed(arch)
    local key = "HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\" .. (arch == "x86" and "X86" or "X64")
    local handle = io.popen('reg query "' .. key .. '" /v Installed 2>nul', "r")
    if not handle then
        return false
    end
    local output = handle:read("*a") or ""
    handle:close()
    return output:match("REG_DWORD%s+0x1%s") ~= nil
end

-- Returns true when php.exe starts. It needs the runtime, so it runs after the runtime
-- is known to be installed, or after it was installed.
local function php_starts(path)
    local startBat = path .. "\\php_start.bat"
    local _, err = util.write_file(startBat, '"' .. path .. '\\php.exe" -n -r "exit(0);"')
    if err ~= nil then
        error(err)
    end
    local started = os.execute('""' .. startBat .. '""')
    os.remove(startBat)
    return started == 0
end

-- Installs the runtime silently, run by a batch file. Exit 100: the installer is not
-- signed by Microsoft, so it does not run. Exit 101: Windows does not start it, for
-- instance because the permission prompt was declined. Exit 102: PowerShell itself
-- failed. Any other code is the installer's own. Without administrator rights the
-- installer starts elevated, which shows Windows' permission prompt.
local INSTALL_REDIST_PS1 = [[
param([string] $Installer)
trap { exit 102 }
$signature = Get-AuthenticodeSignature -LiteralPath $Installer
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike '*O=Microsoft Corporation*') { exit 100 }
$admin = (New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$start = @{ FilePath = $Installer; ArgumentList = @('/install', '/quiet', '/norestart'); Wait = $true; PassThru = $true }
if (-not $admin) { $start['Verb'] = 'RunAs' }
try {
    $process = Start-Process @start
} catch {
    exit 101
}
exit $process.ExitCode
]]

-- Downloads the runtime that matches the PHP build, and installs it. The download is
-- not pinned, because Microsoft's redirect moves with each update: the installer must
-- carry Microsoft's signature instead. Exit 3010 means the runtime is installed and a
-- restart is pending, so the php.exe check after this one decides.
local function install_vc_redist(path, arch)
    local url = "https://aka.ms/vs/17/release/vc_redist." .. arch .. ".exe"
    local manual = string.format(
        "Install the %s build from %s yourself, then install PHP again. Composer was not installed.",
        arch,
        url
    )
    local resp, err = http.get({ url = url })
    if err ~= nil or resp == nil or resp.status_code ~= 200 then
        error(
            string.format(
                "The Visual C++ Redistributable is not installed, and it could not be downloaded from %s. %s",
                url,
                manual
            )
        )
    end

    local installer = path .. "\\vc_redist." .. arch .. ".exe"
    local script = path .. "\\install_vc_redist.ps1"
    local runBat = path .. "\\install_vc_redist.bat"
    _, err = util.write_file(script, INSTALL_REDIST_PS1)
    if err ~= nil then
        error(err)
    end
    -- PowerShell 7 adds its modules to PSModulePath, which this process inherits, and
    -- Windows PowerShell cannot load its Security module from there. The batch file
    -- gives Windows PowerShell its own module path, and runs it by its full path.
    local runCommand = string.format(
        '@set "PSModulePath=%%SystemRoot%%\\System32\\WindowsPowerShell\\v1.0\\Modules"\n"%%SystemRoot%%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%s" -Installer "%s"',
        script,
        installer
    )
    _, err = util.write_file(runBat, runCommand)
    if err ~= nil then
        error(err)
    end
    -- The installer is an executable, so its bytes are written exactly as downloaded.
    _, err = util.write_binary_file(installer, resp.body)
    if err ~= nil then
        error(err)
    end
    local code = os.execute('""' .. runBat .. '""')
    os.remove(runBat)
    os.remove(script)
    os.remove(installer)
    if code == 100 then
        error(
            "The Visual C++ Redistributable from "
                .. url
                .. " is not signed by Microsoft, so it was not run. "
                .. manual
        )
    elseif code == 101 then
        error(
            "Windows did not start the Visual C++ Redistributable installer, for instance because its permission prompt was declined. "
                .. manual
        )
    elseif code == 102 then
        error("PowerShell could not check or start the Visual C++ Redistributable installer. " .. manual)
    elseif code ~= 0 and code ~= 3010 then
        error("The Visual C++ Redistributable installer exited with code " .. tostring(code) .. ". " .. manual)
    end
end

function InstallComposerForWin(path)
    local arch = RUNTIME.archType == "386" and "x86" or "x64"
    -- php.exe is not run while the runtime is missing: without it, Windows reports the
    -- missing DLL in a message box, and the install must not wait for someone to close it.
    if not redist_installed(arch) then
        install_vc_redist(path, arch)
    end
    if not php_starts(path) then
        error(
            "php.exe does not start. The PHP builds need the Microsoft Visual C++ 2015-2022 Redistributable: restart Windows and install PHP again. If it still fails, repair the Redistributable from Apps & Features. Composer was not installed."
        )
    end
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

function CompileInstallPHP(path, version, zts)
    if not version:match("^%d+%.%d+%.%d+$") then
        error("Invalid PHP source version: " .. tostring(version))
    end
    local install = RUNTIME.pluginDirPath .. "/bin/install"
    os.execute('chmod +x "' .. install .. '"')
    -- --zts comes before the install path, which bin/install reads first.
    local option = zts and "--zts " or ""
    local code = os.execute('"' .. install .. '" ' .. option .. '"' .. path .. '" ' .. version)
    if code ~= 0 then
        error("Compilation Failure.")
    end
end
