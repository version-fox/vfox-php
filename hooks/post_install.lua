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
    content = content:gsub(';%s*extension_dir = "ext"', 'extension_dir = "./ext"')
    content = content:gsub(';extension=openssl', 'extension=openssl')
    content = content:gsub(';extension=php_openssl.dll', 'extension=php_openssl.dll')
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

    local phpPath = path .. "\\php.exe"
    local setupPath = setup
    local installPath = path
    local execString = phpPath .. ' ' .. setupPath .. ' --install-dir=' .. installPath
    

    if RUNTIME.osType == 'windows' then
        phpPath = "\"" .. phpPath .. "\""
        setupPath = "\"" .. setupPath .. "\""
        installPath = "\"" .. installPath .. "\""
        
        local winPrefix = ''

        util.write_file(path .. '\\composer_install.bat', winPrefix .. phpPath .. ' ' .. setupPath .. ' --install-dir=' .. installPath)

        execString = path .. '\\composer_install.bat'
    end

    local code = os.execute(execString)
    if code ~= 0 then
        error('Failed to install composer.')
    end

    os.remove(setup)

    if RUNTIME.osType == 'windows' then
        os.remove(path .. '\\composer_install.bat')
    end

    util.write_file(path .. '\\composer.bat', '@php "%~dp0composer.phar" %*')
end

function CompileInstallPHP(path)
    os.execute('chmod +x ' .. RUNTIME.pluginDirPath .. '/bin/install')
    local code = os.execute(RUNTIME.pluginDirPath .. '/bin/install ' .. path)
    if code ~= 0 then
        error('Compilation Failure.')
    end
end
