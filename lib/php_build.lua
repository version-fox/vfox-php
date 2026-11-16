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

-- Builds PHP from its source on Linux and macOS, and installs Composer into the build.
-- The PostInstall hook calls install, and the PreUninstall hook calls remove_build.
--
-- Everything that depends on the machine is read through php_build.probe, so that the
-- tests can answer for a machine of their own. Every value that goes into a shell command
-- is quoted with php_build.quote.

local http = require("http")
local util = require("util")

local php_build = {}

-- The checks of the machine. Each one answers whether something is there.
local probe = {}
php_build.probe = probe

-- The file that the build leaves in conf.d, where system-wide options go.
local PHP_INI = "# add system-wide php configuration options here\n"

-- Prints a message for the user. The build printed these on stderr before. The tests
-- replace it to read the messages.
php_build.notice = function(message)
    print(message)
end

-- Quotes s as one word for the shell.
function php_build.quote(s)
    return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

-- Runs a command in the shell. It succeeds when the command exits with 0, which is all
-- that vfox's os.execute reports: 0 or 1.
local function succeeds(command)
    return os.execute(command) == 0
end

-- The output of a command, without the line break at its end.
local function output(command)
    local handle = io.popen(command, "r")
    if handle == nil then
        return ""
    end
    local text = handle:read("*a") or ""
    handle:close()
    return (string.gsub(text, "%s+$", ""))
end

local function has_space(text)
    return string.find(text, "%s") ~= nil
end

local function parent_of(path)
    return string.match(path, "^(.*)/[^/]*$") or "."
end

local function exists(path)
    return succeeds("test -e " .. php_build.quote(path))
end

local function is_link(path)
    return succeeds("test -L " .. php_build.quote(path))
end

local function make_dir(path)
    if not succeeds("mkdir -p " .. php_build.quote(path)) then
        error("Failed to create " .. path, 0)
    end
end

-- Removes a file or a directory tree, when there is one, as rm -rf does.
local function remove_tree(path)
    if exists(path) and not succeeds("rm -rf " .. php_build.quote(path)) then
        error("Failed to remove " .. path, 0)
    end
end

-- Moves a path to a new name that does not exist yet, as mv does.
local function move_path(from, to)
    if not succeeds("mv " .. php_build.quote(from) .. " " .. php_build.quote(to)) then
        error("Failed to move " .. from .. " to " .. to, 0)
    end
end

-- Makes a symbolic link at link that points to target, as ln -s does.
local function link_path(target, link)
    if not succeeds("ln -s " .. php_build.quote(target) .. " " .. php_build.quote(link)) then
        error("Failed to link " .. link .. " to " .. target, 0)
    end
end

-- Succeeds when the tool runs with --version, which shows that it is installed.
function probe.tool(name)
    return succeeds(php_build.quote(name) .. " --version >/dev/null 2>&1")
end

-- Succeeds when pkg-config knows every module that the name lists, separated by spaces.
function probe.pkg(name)
    local modules = {}
    for module in string.gmatch(name, "%S+") do
        table.insert(modules, php_build.quote(module))
    end
    return succeeds("pkg-config --exists " .. table.concat(modules, " ") .. " >/dev/null 2>&1")
end

-- Succeeds when the compiler finds the header. The compiler reads a file that holds the
-- include line, so the test does not depend on how the shell passes it on.
function probe.header(header)
    local file = os.tmpname()
    local written = util.write_file(file, "#include <" .. header .. ">\n")
    local found = written and succeeds("cc -E -x c " .. php_build.quote(file) .. " >/dev/null 2>&1")
    os.remove(file)
    return found and true or false
end

-- Succeeds when the dynamic linker's cache lists the library and the compiler finds its
-- header. configure needs both.
function probe.library(library, header)
    local cache = output("ldconfig -p 2>/dev/null || /sbin/ldconfig -p 2>/dev/null")
    return string.find(cache, library, 1, true) ~= nil and probe.header(header)
end

-- The prefix of an installed Homebrew formula, or nil when it is not installed.
function probe.brew_prefix(formula)
    if output("brew ls --versions " .. php_build.quote(formula) .. " 2>/dev/null") == "" then
        return nil
    end
    local prefix = output("brew --prefix " .. php_build.quote(formula) .. " 2>/dev/null")
    if prefix == "" then
        return nil
    end
    return prefix
end

-- Homebrew answers --version when it is installed.
function probe.brew_installed()
    return output("brew --version 2>/dev/null") ~= ""
end

-- The checksum that names the build directory of an install path (cksum's first number).
function probe.checksum(text)
    return string.match(output("printf '%s' " .. php_build.quote(text) .. " | cksum"), "^(%d+)")
end

-- The id of the user, which names the build directory under /var/tmp.
function probe.user_id()
    return output("id -u")
end

-- The target of a symbolic link.
function probe.link_target(path)
    return output("readlink " .. php_build.quote(path))
end

-- Succeeds when PHP_VERSION is at least major.minor. A version that cannot be read counts
-- as the newest PHP, so its options are the ones that the newest PHP takes.
function php_build.at_least(version, major, minor)
    local vmajor, vminor = string.match(version or "", "^(%d+)%.(%d+)")
    if vmajor == nil then
        return true
    end
    vmajor, vminor = tonumber(vmajor), tonumber(vminor)
    return vmajor > major or (vmajor == major and vminor >= minor)
end

-- Succeeds when PHP_VERSION is older than major.minor.
function php_build.before(version, major, minor)
    return not php_build.at_least(version, major, minor)
end

-- The value of a switch such as PHP_WITHOUT_PEAR. It is "no" when the variable is unset
-- or empty, which is how the switches have always read.
local function switch(name)
    local value = os.getenv(name)
    if value == nil or value == "" then
        return "no"
    end
    return value
end

-- The operating system in lower case: "linux", "darwin" or "windows".
local function operating_system()
    return string.lower(RUNTIME.osType or "")
end

-- PHP_CONFIGURE_OPTIONS, when it is set. Its words then replace the platform options.
local function explicit_options()
    local value = os.getenv("PHP_CONFIGURE_OPTIONS")
    if value == nil or value == "" then
        return nil
    end
    return value
end

local function words(text)
    local list = {}
    for word in string.gmatch(text, "%S+") do
        table.insert(list, word)
    end
    return list
end

local function extend(list, more)
    for _, item in ipairs(more) do
        table.insert(list, item)
    end
    return list
end

-- The Homebrew OpenSSL that a PHP version builds against. PHP 7.1 to 8.0 need OpenSSL 1.1,
-- and PHP 8.1 and later take OpenSSL 3. See
-- https://www.php.net/manual/en/openssl.requirements.php
local function openssl_prefix(version)
    local formula = "openssl@1.1"
    if php_build.at_least(version, 8, 1) then
        formula = "openssl@3"
    end
    local prefix = probe.brew_prefix(formula)
    if prefix == nil then
        error(
            "ERROR: PHP " .. version .. " requires " .. formula .. "; install a compatible dependency before building.",
            0
        )
    end
    return prefix
end

-- Linux: the libraries of the system. configure finds them with pkg-config and the
-- compiler. The ones that are found are passed, and the others are reported.
local function linux_platform_options(version)
    local options =
        { "--with-openssl", "--with-curl", "--with-zlib", "--with-readline", "--with-gettext", "--with-xsl" }
    if probe.library("libgmp.so", "gmp.h") then
        table.insert(options, "--with-gmp")
    else
        php_build.notice("gmp not found, not including in installation")
    end
    -- The sodium extension came with PHP 7.2, and an older configure does not take the option.
    if php_build.at_least(version, 7, 2) then
        if probe.library("libsodium.so", "sodium.h") then
            table.insert(options, "--with-sodium")
        else
            php_build.notice("sodium not found, not including in installation")
        end
    end
    return options
end

-- macOS: the Homebrew formulae. Each one that is installed gives its prefix to configure.
-- Each option is taken only by the PHP versions named beside it, since configure ignores
-- the rest.
local function darwin_platform_options(version)
    if not probe.brew_installed() then
        error("ERROR: Please install homebrew for OSX", 0)
    end
    local options = {}
    local openssl = openssl_prefix(version)

    local gmp = probe.brew_prefix("gmp")
    if gmp then
        table.insert(options, "--with-gmp=" .. gmp)
    else
        php_build.notice("gmp not found, not including in installation")
    end
    if php_build.at_least(version, 7, 2) then
        local sodium = probe.brew_prefix("libsodium")
        if sodium then
            table.insert(options, "--with-sodium=" .. sodium)
        else
            php_build.notice("sodium not found, not including in installation")
        end
    end

    local function prefixed(flag, formula, taken)
        if not taken then
            return
        end
        local prefix = probe.brew_prefix(formula)
        if prefix then
            table.insert(options, flag .. "=" .. prefix)
        end
    end
    prefixed("--with-freetype-dir", "freetype", php_build.before(version, 7, 4))
    prefixed("--with-gettext", "gettext", true)
    prefixed("--with-icu-dir", "icu4c", php_build.before(version, 7, 4))
    prefixed("--with-jpeg-dir", "jpeg", php_build.before(version, 7, 4))
    prefixed("--with-webp-dir", "webp", php_build.at_least(version, 7, 0) and php_build.before(version, 7, 4))
    prefixed("--with-png-dir", "libpng", php_build.before(version, 7, 4))
    table.insert(options, "--with-openssl=" .. openssl)
    prefixed("--with-libxml-dir", "libxml2", php_build.before(version, 7, 4))
    prefixed("--with-xsl", "libxslt", true)
    prefixed("--with-zlib-dir", "zlib", php_build.before(version, 8, 4))
    prefixed("--with-libzip", "libzip", php_build.at_least(version, 5, 6) and php_build.before(version, 7, 4))
    prefixed("--with-readline", "readline", true)
    prefixed("--with-libedit", "libedit", true)
    prefixed("--with-bz2", "bzip2", true)
    prefixed("--with-iconv", "libiconv", true)
    return options
end

-- The options that every build takes, for the install path that the build is made into.
local function global_options(prefix)
    return {
        "--prefix=" .. prefix,
        "--enable-bcmath",
        "--enable-calendar",
        "--enable-dba",
        "--enable-exif",
        "--enable-fpm",
        "--enable-ftp",
        "--enable-intl",
        "--enable-mbstring",
        "--enable-mysqlnd",
        "--enable-pcntl",
        "--enable-shmop",
        "--enable-soap",
        "--enable-sockets",
        "--enable-sysvmsg",
        "--enable-sysvsem",
        "--enable-sysvshm",
        "--sysconfdir=" .. prefix,
        "--with-config-file-path=" .. prefix,
        "--with-config-file-scan-dir=" .. prefix .. "/conf.d",
        "--with-curl",
        "--with-fpm-group=www-data",
        "--with-fpm-user=www-data",
        "--with-mhash",
        "--with-mysqli=mysqlnd",
        "--with-pdo-mysql=mysqlnd",
        "--with-zlib",
        "--without-snmp",
    }
end

-- The options that some PHP versions take and others do not. configure ignores an option
-- that a version does not take, and most versions warn about it, so each option is passed
-- only to the versions that take it.
local function version_options(version)
    local options = {}
    if php_build.at_least(version, 5, 4) then
        table.insert(options, "--enable-mbregex")
    end
    if php_build.before(version, 7, 4) then
        extend(options, { "--enable-wddx", "--enable-zip", "--with-gd" })
    else
        extend(options, { "--enable-gd", "--with-external-gd", "--with-zip" })
    end
    if php_build.before(version, 8, 0) then
        table.insert(options, "--with-xmlrpc")
    end
    if php_build.before(version, 7, 2) then
        table.insert(options, "--enable-gd-native-ttf")
    end
    if php_build.before(version, 7, 0) then
        table.insert(options, "--with-mysql=mysqlnd")
    end
    return options
end

-- The configure arguments of a build made into prefix: the platform options, then the
-- options that every build takes and the version options, then PEAR, PCRE JIT and ZTS.
-- With PHP_CONFIGURE_OPTIONS set, its words replace the platform options.
function php_build.configure_arguments(prefix, version, zts)
    local platform
    if explicit_options() ~= nil then
        platform = words(explicit_options())
    elseif operating_system() == "darwin" then
        platform = darwin_platform_options(version)
    else
        platform = linux_platform_options(version)
    end

    local args = extend(platform, global_options(prefix))
    extend(args, version_options(version))

    -- PHP 7.4 and later warn that --with-pear is deprecated, and PHP 8.4 and later warn
    -- that --with-mhash is. Both stay: PEAR is installed only when --with-pear is given,
    -- and the mhash functions are built only with --with-mhash.
    if switch("PHP_WITHOUT_PEAR") ~= "no" then
        table.insert(args, "--without-pear")
    else
        table.insert(args, "--with-pear")
    end

    -- PCRE JIT is on in PHP's own configuration, so it stays on unless PHP_WITHOUT_PCRE_JIT
    -- asks for --without-pcre-jit. PHP 5.x does not take that option.
    if switch("PHP_WITHOUT_PCRE_JIT") ~= "no" and php_build.at_least(version, 7, 0) then
        table.insert(args, "--without-pcre-jit")
    end

    -- A thread-safe build. PHP 5.x and 7.x configure it with --enable-maintainer-zts, and
    -- PHP 8.0 and later with --enable-zts.
    if zts then
        if string.match(version, "^[57]%.") then
            table.insert(args, "--enable-maintainer-zts")
        else
            table.insert(args, "--enable-zts")
        end
    end
    return args
end

-- The build dependencies of PHP on Linux, as {kind, name, what needs it, package}. A tool
-- runs with --version. A pkg is one or more pkg-config modules. A header is found by the
-- compiler. The last four are needed by the platform options, which PHP_CONFIGURE_OPTIONS
-- replaces, so they are checked only when it is not set.
local function linux_requirements(explicit)
    local list = {
        { "tool", "cc", "a C compiler", "build-essential" },
        { "tool", "make", "the build", "build-essential" },
        { "tool", "autoconf", "buildconf", "autoconf" },
        { "tool", "pkg-config", "the libraries that configure looks up with pkg-config", "pkg-config" },
        { "tool", "curl", "the Composer installer", "curl" },
        { "pkg", "zlib", "--with-zlib", "zlib1g-dev" },
        { "pkg", "libxml-2.0", "the xml, dom, simplexml and soap extensions", "libxml2-dev" },
        { "pkg", "libcurl", "--with-curl", "libcurl4-openssl-dev" },
        { "pkg", "gdlib", "--with-external-gd", "libgd-dev" },
        { "pkg", "libpng", "the PNG support of gd", "libpng-dev" },
        { "pkg", "libzip", "--with-zip", "libzip-dev" },
        { "pkg", "icu-uc icu-io icu-i18n", "--enable-intl", "libicu-dev" },
        { "pkg", "oniguruma", "--enable-mbregex", "libonig-dev" },
        { "pkg", "sqlite3", "the sqlite3 and pdo_sqlite extensions", "libsqlite3-dev" },
    }
    if not explicit then
        extend(list, {
            { "header", "openssl/ssl.h", "--with-openssl", "libssl-dev" },
            { "header", "readline/readline.h", "--with-readline", "libreadline-dev" },
            { "header", "libintl.h", "--with-gettext", "libc6-dev" },
            { "pkg", "libxslt", "--with-xsl", "libxslt-dev" },
        })
    end
    return list
end

-- The Linux build dependencies that are missing, with what needs each one, and the
-- packages that provide them, each listed once.
function php_build.missing_dependencies(explicit)
    local missing, packages, seen = {}, {}, {}
    for _, requirement in ipairs(linux_requirements(explicit)) do
        local kind, name, need, package = requirement[1], requirement[2], requirement[3], requirement[4]
        local found
        if kind == "tool" then
            found = probe.tool(name)
        elseif kind == "pkg" then
            found = probe.pkg(name)
        else
            found = probe.header(name)
        end
        if not found then
            table.insert(missing, { name = name, need = need })
            if not seen[package] then
                seen[package] = true
                table.insert(packages, package)
            end
        end
    end
    return missing, packages
end

-- Stops the install before anything is moved or compiled when a dependency is missing.
local function check_linux_dependencies(explicit)
    local missing, packages = php_build.missing_dependencies(explicit)
    if #missing == 0 then
        return
    end
    local lines = {
        "ERROR: PHP cannot be built, because these build dependencies are missing. Nothing was compiled:",
    }
    for _, item in ipairs(missing) do
        table.insert(lines, "  - " .. item.name .. ": " .. item.need)
    end
    table.insert(lines, "Install them and run vfox install again. The packages are named for Debian and Ubuntu:")
    table.insert(lines, "  sudo apt-get install --assume-yes " .. table.concat(packages, " "))
    error(table.concat(lines, "\n"), 0)
end

-- The directory that PHP is built in, when the install path holds no space: the first of
-- the XDG data directory, the data directory under HOME, and /var/tmp, that holds no space.
function php_build.build_base()
    local candidates = {}
    local xdg = os.getenv("XDG_DATA_HOME")
    if xdg ~= nil and xdg ~= "" then
        table.insert(candidates, xdg .. "/vfox-php")
    end
    local home = os.getenv("HOME")
    if home ~= nil and home ~= "" then
        table.insert(candidates, home .. "/.local/share/vfox-php")
    end
    table.insert(candidates, "/var/tmp/vfox-php-" .. probe.user_id())
    for _, candidate in ipairs(candidates) do
        if not has_space(candidate) then
            return candidate
        end
    end
    error("ERROR: no directory without spaces to build PHP in", 0)
end

-- The build directory of an install path with a space. Its name is the checksum of the
-- path, so two install paths never share one.
function php_build.build_dir_for(install_path)
    return php_build.build_base() .. "/builds/" .. probe.checksum(install_path)
end

-- Removes what a failed build leaves: the link at the install path, the build directory
-- and the source directory.
local function discard_build(install_path, build_dir, source_path)
    if is_link(install_path) then
        os.remove(install_path)
    end
    remove_tree(build_dir)
    remove_tree(source_path)
end

-- Removes the build directory that an install path with a space links to. vfox removes
-- the link itself. This removes what the link points to, and nothing else.
function php_build.remove_build(install_path)
    if not is_link(install_path) then
        return
    end
    local target = probe.link_target(install_path)
    if string.find(target, "/vfox%-php.-/builds/%d") == nil then
        error("ERROR: " .. install_path .. " links to " .. target .. ", which is not a vfox-php build directory", 0)
    end
    remove_tree(target)
end

-- The environment of a Homebrew build on macOS, as a shell prefix: bison goes first on
-- PATH, and the pkg-config directories of the formulae that have one go first on
-- PKG_CONFIG_PATH. OpenSSL goes first when PHP_CONFIGURE_OPTIONS does not name it.
local function darwin_environment(version, explicit)
    local commands = {}
    local bison = probe.brew_prefix("bison")
    if bison then
        table.insert(commands, "export PATH=" .. php_build.quote(bison .. "/bin:" .. (os.getenv("PATH") or "")))
    end

    local pkg_config = os.getenv("PKG_CONFIG_PATH") or ""
    local changed = false
    local function prepend(prefix)
        if prefix ~= nil then
            pkg_config = prefix .. "/lib/pkgconfig:" .. pkg_config
            changed = true
        end
    end
    prepend(probe.brew_prefix("icu4c"))
    prepend(probe.brew_prefix("krb5"))
    prepend(probe.brew_prefix("libedit"))
    prepend(probe.brew_prefix("libxml2"))
    prepend(probe.brew_prefix("libxslt"))
    if not explicit then
        prepend(openssl_prefix(version))
    end
    if changed then
        table.insert(commands, "export PKG_CONFIG_PATH=" .. php_build.quote(pkg_config))
    end

    if #commands == 0 then
        return ""
    end
    return table.concat(commands, "; ") .. "; "
end

-- Runs the steps of the build in the source directory, each with a message, as bin/install did.
local function compile(source_path, environment, args)
    local quoted = {}
    for _, arg in ipairs(args) do
        table.insert(quoted, php_build.quote(arg))
    end
    local steps = {
        { "Running buildconfig...", "./buildconf --force" },
        { "Running ./configure " .. table.concat(args, " "), "./configure " .. table.concat(quoted, " ") },
        { "Running make", "make" },
        { "Running make install...", "make install" },
    }
    for _, step in ipairs(steps) do
        php_build.notice(step[1])
        local command = "cd " .. php_build.quote(source_path) .. " && " .. environment .. step[2]
        if not succeeds(command) then
            error("Compilation Failure: " .. step[2] .. " did not succeed.", 0)
        end
    end
end

-- Downloads a file for Composer, or fails with the reason.
local function fetch(url)
    local response, err = http.get({ url = url })
    if err ~= nil or response == nil then
        error("Failed to download " .. url .. ": " .. tostring(err or "no response"), 0)
    end
    if response.status_code ~= 200 then
        error("Failed to download " .. url .. ": HTTP " .. tostring(response.status_code), 0)
    end
    return response.body
end

-- Installs Composer into the bin directory of the build. The installer must match the sha384
-- that Composer publishes, and PHP computes that hash, so no crypto library is needed. A
-- mismatch removes the installer and stops the install.
local function install_composer(install_path)
    local bin = install_path .. "/bin"
    local expected = string.gsub(fetch("https://composer.github.io/installer.sig"), "%s", "")
    local setup = bin .. "/composer-setup.php"
    local written, err = util.write_file(setup, fetch("https://getcomposer.org/installer"))
    if not written then
        error(err, 0)
    end

    local php = php_build.quote(bin .. "/php")
    local check = "if (hash_file('sha384', '" .. setup .. "') === '" .. expected .. "') { exit(0); } exit(1);"
    if not succeeds(php .. " -r " .. php_build.quote(check)) then
        os.remove(setup)
        error(
            "The Composer installer does not match the sha384 that Composer publishes; Composer was not installed.",
            0
        )
    end
    local installed = succeeds(
        php .. " " .. php_build.quote(setup) .. " --install-dir=" .. php_build.quote(bin) .. " --filename=composer"
    )
    os.remove(setup)
    if not installed then
        error("Failed to install composer.", 0)
    end
end

-- Builds PHP from its source in install_path, which holds the release, and installs Composer
-- into it. A path with a space is built in a directory without spaces, and the path becomes a
-- link to that directory. Any failure after the source is moved removes that build again.
function php_build.install(install_path, version, zts)
    local darwin = operating_system() == "darwin"
    local explicit = explicit_options() ~= nil
    if darwin then
        if not probe.brew_installed() then
            error("ERROR: Please install homebrew for OSX", 0)
        end
    else
        check_linux_dependencies(explicit)
    end

    local prefix = install_path
    local source_path = install_path .. "_source"
    local build_dir = nil
    if has_space(install_path) then
        build_dir = php_build.build_dir_for(install_path)
        prefix = build_dir
        source_path = build_dir .. ".source"
        remove_tree(build_dir)
        remove_tree(source_path)
        make_dir(parent_of(build_dir))
    end

    local args = php_build.configure_arguments(prefix, version, zts)
    local environment = ""
    if darwin then
        environment = darwin_environment(version, explicit)
    end

    local ok, err = pcall(function()
        move_path(install_path, source_path)
        if build_dir then
            link_path(build_dir, install_path)
        end
        compile(source_path, environment, args)

        -- it's not obvious where php.ini should be placed, so the build leaves one in conf.d
        make_dir(install_path .. "/conf.d")
        local written, write_err = util.write_file(install_path .. "/conf.d/php.ini", PHP_INI)
        if not written then
            error(write_err, 0)
        end
        remove_tree(source_path)
        install_composer(install_path)
    end)
    if not ok then
        if build_dir then
            discard_build(install_path, build_dir, source_path)
        end
        error(err, 0)
    end
end

return php_build
