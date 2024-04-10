local http = require('http')
local util = require('util')

--- Extension point, called after PreInstall, can perform additional operations,
--- such as file operations for the SDK installation directory or compile source code
--- Currently can be left unimplemented!
function PLUGIN:PostInstall(ctx)
    local sdkInfo = ctx.sdkInfo['php']
    local path = sdkInfo.path
    if RUNTIME.osType == 'windows' then
        InstallComposerForWin(path)
    else
        CompileInstallPHP(path)
    end
end

function InstallComposerForWin(path)
    local content, err = util.read_file(path .. '\\php.ini-development')
    if err ~= nil then
        error(err)
    end
    content = content:gsub(';extension_dir = "ext"', 'extension_dir = "./ext"')
    content = content:gsub(';extension=openssl', 'extension=openssl')
    _, err = util.write_file(path .. '\\php.ini', content)
    if err ~= nil then
        error(err)
    end

    local resp, err = http.get({
        url = 'https://getcomposer.org/installer'
    })
    local setup = path .. '\\composer-setup.php'
    _, err = util.write_file(setup, resp.body)
    if err ~= nil then
        error(err)
    end

    local code = os.execute(path .. '\\php.exe ' .. setup .. ' --install-dir=' .. path)
    if code ~= 0 then
        error('Failed to install composer.')
    end

    os.remove(setup)
    util.write_file(path .. '\\composer.bat', '@php "%~dp0composer.phar" %*')
end

function CompileInstallPHP(path)
    RUNTIME.pluginDirPath = '~/.version-fox/plugin/php'
    os.execute('chmod +x ' .. RUNTIME.pluginDirPath .. '/bin/install')
    local code = os.execute(RUNTIME.pluginDirPath .. '/bin/install ' .. path)
    if code ~= 0 then
        error('Compilation Failure.')
    end
end
