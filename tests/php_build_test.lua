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

-- The build of PHP on Linux and macOS (lib/php_build.lua), on a fake machine. The commands
-- the build runs, the files it writes, the moves and links it makes are recorded, and the
-- fake machine answers the commands that check it. Nothing here touches the real system.
package.path = "./lib/?.lua;" .. package.path
PLUGIN = {}
RUNTIME = { osType = "linux", pluginDirPath = "/plugins/php" }

local util = require("util")

-- What the fake machine has, and what the build did to it. Every test starts with a fresh one.
-- The table is the same for the whole file, and only its fields change: the Lua runtime used
-- here does not see a local that a function has rebound, as windows_test.lua notes.
local H = {}

local function set_of(list)
    local set = {}
    for _, item in ipairs(list) do
        set[item] = true
    end
    return set
end

-- A Debian-like Linux with every build dependency: the tools, the pkg-config modules, the
-- headers, and the gmp and sodium libraries.
local function fresh(overrides)
    local defaults = {
        tools = set_of({ "cc", "make", "autoconf", "pkg-config", "curl" }),
        pkgs = set_of({
            "zlib",
            "libxml-2.0",
            "libcurl",
            "gdlib",
            "libpng",
            "libzip",
            "icu-uc",
            "icu-io",
            "icu-i18n",
            "oniguruma",
            "sqlite3",
            "libxslt",
        }),
        headers = set_of({ "openssl/ssl.h", "readline/readline.h", "libintl.h", "gmp.h", "sodium.h" }),
        libraries = "libgmp.so.10 => /lib/libgmp.so.10\nlibsodium.so.23 => /lib/libsodium.so.23\n",
        formulae = {},
        brew = false,
        env = { HOME = "/home/user", PATH = "/usr/bin:/bin" },
        checksum = "4242",
        sha_ok = true,
        fail = {},
        commands = {},
        files = {},
        moves = {},
        links = {},
        removed = {},
        existing = {},
        dirs = {},
        urls = {},
        http = {
            ["https://getcomposer.org/installer"] = { status_code = 200, body = "<?php echo 'installer';" },
            ["https://composer.github.io/installer.sig"] = { status_code = 200, body = "ABCDEF\n" },
        },
        notices = {},
    }
    for key in pairs(H) do
        H[key] = nil
    end
    for key, value in pairs(defaults) do
        H[key] = value
    end
    for key, value in pairs(overrides or {}) do
        H[key] = value
    end
end
fresh()

-- The answer of the fake machine to a command: 0 when the check passes, 1 otherwise.
local function answer(command)
    for _, pattern in ipairs(H.fail) do
        if string.find(command, pattern, 1, true) then
            return 1
        end
    end
    local tool = string.match(command, "^'([^']+)' %-%-version")
    if tool then
        return H.tools[tool] and 0 or 1
    end
    if string.find(command, "^pkg%-config %-%-exists") then
        for module in string.gmatch(command, "'([^']+)'") do
            if not H.pkgs[module] then
                return 1
            end
        end
        return 0
    end
    local file = string.match(command, "^cc %-E %-x c '([^']+)'")
    if file then
        local header = string.match(H.files[file] or "", "#include <([^>]+)>")
        return (header and H.headers[header]) and 0 or 1
    end
    local path = string.match(command, "^test %-e '(.*)'$")
    if path then
        return H.existing[path] and 0 or 1
    end
    path = string.match(command, "^test %-L '(.*)'$")
    if path then
        return H.links[path] and 0 or 1
    end
    if string.find(command, "hash_file", 1, true) then
        return H.sha_ok and 0 or 1
    end
    path = string.match(command, "^mkdir %-p '(.*)'$")
    if path then
        H.dirs[path] = true
    end
    local from, to = string.match(command, "^mv '(.-)' '(.-)'$")
    if from then
        table.insert(H.moves, { from, to })
        return 0
    end
    local target, link = string.match(command, "^ln %-s '(.-)' '(.-)'$")
    if target then
        H.links[link] = target
        return 0
    end
    path = string.match(command, "^rm %-rf '(.*)'$")
    if path then
        table.insert(H.removed, path)
    end
    return 0
end

-- The output of a command on the fake machine.
local function output_of(command)
    if command == "ldconfig -p 2>/dev/null || /sbin/ldconfig -p 2>/dev/null" then
        return H.libraries
    end
    if command == "brew --version 2>/dev/null" then
        return H.brew and "Homebrew 4.5.0\n" or ""
    end
    if command == "id -u" then
        return "1000\n"
    end
    local formula = string.match(command, "^brew ls %-%-versions '([^']+)' 2>/dev/null$")
    if formula then
        return H.formulae[formula] and (formula .. " 1.0\n") or ""
    end
    formula = string.match(command, "^brew %-%-prefix '([^']+)' 2>/dev/null$")
    if formula then
        return H.formulae[formula] or ""
    end
    if string.find(command, "| cksum", 1, true) then
        return H.checksum .. " 5\n"
    end
    local link = string.match(command, "^readlink '(.*)'$")
    if link then
        return H.links[link] or ""
    end
    return ""
end

os.execute = function(command)
    table.insert(H.commands, command)
    return answer(command)
end
io.popen = function(command)
    local text = output_of(command)
    return {
        read = function()
            return text
        end,
        close = function() end,
    }
end
os.getenv = function(name)
    return H.env[name]
end
os.remove = function(path)
    table.insert(H.removed, path)
    return true
end
util.write_file = function(path, content)
    H.files[path] = content
    return true
end
package.preload.http = function()
    return {
        get = function(args)
            table.insert(H.urls, args.url)
            return H.http[args.url] or { status_code = 404, body = "" }
        end,
    }
end

local php_build = require("php_build")
php_build.notice = function(message)
    table.insert(H.notices, message)
end

local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end
    return false
end

-- Whether some entry of the list contains text.
local function mentions(list, text)
    for _, item in ipairs(list) do
        if string.find(item, text, 1, true) then
            return true
        end
    end
    return false
end

-- The commands that run the build itself, which start with cd into the source directory.
local function build_commands()
    local list = {}
    for _, command in ipairs(H.commands) do
        if
            string.find(command, "&& ", 1, true) and string.find(command, "./buildconf", 1, true)
            or string.find(command, "&& ", 1, true) and string.find(command, "./configure", 1, true)
            or string.find(command, "&& make", 1, true)
        then
            table.insert(list, command)
        end
    end
    return list
end

-- The configure arguments of a build, as a set and as a list.
local function configure_of(version, zts)
    local args = php_build.configure_arguments("/fake/prefix", version, zts or false)
    return set_of(args), args
end

-- Asserts that fn fails with a message that contains expected, and returns the message.
local function fails(fn, expected)
    local ok, err = pcall(fn)
    assert(not ok, "the call must fail with " .. expected)
    assert(tostring(err):find(expected, 1, true), tostring(err))
    return tostring(err)
end

-- 1. Version gating and shell quoting.
fresh()
assert(php_build.at_least("5.4.0", 5, 4) and not php_build.at_least("5.3.29", 5, 4))
assert(php_build.at_least("8.1.34", 8, 1) and php_build.before("8.0.30", 8, 1))
assert(php_build.at_least("not-a-version", 7, 4), "a version that cannot be read is the newest PHP")
assert(php_build.quote("a'b") == "'a'\\''b'", php_build.quote("a'b"))
assert(php_build.quote("a b") == "'a b'", php_build.quote("a b"))
print("version gating and shell quoting passed")

-- 2. The Linux options that only some PHP versions take. The flags below are the ones
-- that change between the versions; the others are the same for every version.
local LINUX_GATED = {
    "--enable-mbregex",
    "--enable-wddx",
    "--enable-zip",
    "--with-gd",
    "--enable-gd",
    "--with-external-gd",
    "--with-zip",
    "--with-xmlrpc",
    "--enable-gd-native-ttf",
    "--with-mysql=mysqlnd",
    "--with-sodium",
    "--with-mhash",
    "--with-pear",
}
local LINUX_EXPECTED = {
    ["5.3.29"] = {
        "--with-gd",
        "--enable-wddx",
        "--enable-zip",
        "--with-xmlrpc",
        "--enable-gd-native-ttf",
        "--with-mysql=mysqlnd",
        "--with-mhash",
        "--with-pear",
    },
    ["5.6.40"] = {
        "--enable-mbregex",
        "--with-gd",
        "--enable-wddx",
        "--enable-zip",
        "--with-xmlrpc",
        "--enable-gd-native-ttf",
        "--with-mysql=mysqlnd",
        "--with-mhash",
        "--with-pear",
    },
    ["7.1.33"] = {
        "--enable-mbregex",
        "--with-gd",
        "--enable-wddx",
        "--enable-zip",
        "--with-xmlrpc",
        "--enable-gd-native-ttf",
        "--with-mhash",
        "--with-pear",
    },
    ["7.2.34"] = {
        "--enable-mbregex",
        "--with-gd",
        "--enable-wddx",
        "--enable-zip",
        "--with-xmlrpc",
        "--with-sodium",
        "--with-mhash",
        "--with-pear",
    },
    ["7.4.33"] = {
        "--enable-mbregex",
        "--enable-gd",
        "--with-external-gd",
        "--with-zip",
        "--with-xmlrpc",
        "--with-sodium",
        "--with-mhash",
        "--with-pear",
    },
    ["8.0.30"] = {
        "--enable-mbregex",
        "--enable-gd",
        "--with-external-gd",
        "--with-zip",
        "--with-sodium",
        "--with-mhash",
        "--with-pear",
    },
    ["8.5.12"] = {
        "--enable-mbregex",
        "--enable-gd",
        "--with-external-gd",
        "--with-zip",
        "--with-sodium",
        "--with-mhash",
        "--with-pear",
    },
}
RUNTIME.osType = "linux"
for version, want in pairs(LINUX_EXPECTED) do
    fresh()
    local set = configure_of(version)
    local wanted = set_of(want)
    for _, flag in ipairs(LINUX_GATED) do
        assert(
            (set[flag] or false) == (wanted[flag] or false),
            version .. ": " .. flag .. " is " .. tostring(set[flag]) .. ", want " .. tostring(wanted[flag])
        )
    end
end
print("Linux options follow the PHP version")

-- 3. The macOS formulae that each PHP version takes, and the OpenSSL that it builds with.
RUNTIME.osType = "darwin"
local DARWIN_EXPECTED = {
    ["5.6.40"] = {
        "--with-freetype-dir",
        "--with-icu-dir",
        "--with-jpeg-dir",
        "--with-png-dir",
        "--with-libxml-dir",
        "--with-zlib-dir",
        "--with-libzip",
        "--with-openssl=/fake/openssl@1.1",
        "--with-gettext",
        "--with-xsl",
    },
    ["7.0.33"] = {
        "--with-freetype-dir",
        "--with-icu-dir",
        "--with-jpeg-dir",
        "--with-webp-dir",
        "--with-png-dir",
        "--with-libxml-dir",
        "--with-zlib-dir",
        "--with-libzip",
        "--with-openssl=/fake/openssl@1.1",
        "--with-gettext",
        "--with-xsl",
    },
    ["7.3.33"] = {
        "--with-freetype-dir",
        "--with-icu-dir",
        "--with-jpeg-dir",
        "--with-webp-dir",
        "--with-png-dir",
        "--with-libxml-dir",
        "--with-zlib-dir",
        "--with-libzip",
        "--with-openssl=/fake/openssl@1.1",
        "--with-gettext",
        "--with-xsl",
    },
    ["7.4.33"] = { "--with-zlib-dir", "--with-openssl=/fake/openssl@1.1", "--with-gettext", "--with-xsl" },
    ["8.0.30"] = { "--with-zlib-dir", "--with-openssl=/fake/openssl@1.1", "--with-gettext", "--with-xsl" },
    ["8.4.27"] = { "--with-openssl=/fake/openssl@3", "--with-gettext", "--with-xsl" },
    ["8.5.12"] = { "--with-openssl=/fake/openssl@3", "--with-gettext", "--with-xsl" },
}
-- The libedit flag of each version. Until PHP 7.3 it names the directory, which configure looks
-- in; from PHP 7.4 it comes alone, since configure finds libedit with pkg-config.
local LIBEDIT_FLAG = {
    ["5.6.40"] = "--with-libedit=/fake/libedit",
    ["7.0.33"] = "--with-libedit=/fake/libedit",
    ["7.3.33"] = "--with-libedit=/fake/libedit",
    ["7.4.33"] = "--with-libedit",
    ["8.0.30"] = "--with-libedit",
    ["8.4.27"] = "--with-libedit",
    ["8.5.12"] = "--with-libedit",
}
local DARWIN_FLAGS = {
    "--with-freetype-dir",
    "--with-icu-dir",
    "--with-jpeg-dir",
    "--with-webp-dir",
    "--with-png-dir",
    "--with-libxml-dir",
    "--with-zlib-dir",
    "--with-libzip",
    "--with-openssl=/fake/openssl@1.1",
    "--with-openssl=/fake/openssl@3",
    "--with-gettext",
    "--with-xsl",
}
local all_formulae = {}
for _, formula in ipairs({
    "bison",
    "bzip2",
    "freetype",
    "gettext",
    "icu4c",
    "jpeg",
    "krb5",
    "libedit",
    "libiconv",
    "libpng",
    "libxml2",
    "libxslt",
    "libzip",
    "openssl@1.1",
    "openssl@3",
    "readline",
    "webp",
    "zlib",
    "gmp",
    "libsodium",
}) do
    all_formulae[formula] = "/fake/" .. formula
end
-- Whether a configure argument names the flag, with or without its prefix (--with-x=/prefix).
local function taken(args, flag)
    for _, arg in ipairs(args) do
        if arg == flag or arg:sub(1, #flag + 1) == flag .. "=" then
            return true
        end
    end
    return false
end

for version, want in pairs(DARWIN_EXPECTED) do
    fresh({ brew = true, formulae = all_formulae })
    local set, args = configure_of(version)
    local wanted = set_of(want)
    for _, flag in ipairs(DARWIN_FLAGS) do
        local expect = wanted[flag] or false
        local got = taken(args, flag)
        assert(got == expect, version .. ": " .. flag .. " is " .. tostring(got) .. ", want " .. tostring(expect))
    end
    -- The version takes its formula's prefix: the other OpenSSL never appears.
    local other = version:match("^8%.[1-9]") and "--with-openssl=/fake/openssl@1.1" or "--with-openssl=/fake/openssl@3"
    assert(not set[other], version .. " must not take " .. other)
    -- Every formula that is always taken appears with its prefix.
    for _, flag in ipairs({
        "--with-gettext=/fake/gettext",
        "--with-xsl=/fake/libxslt",
        "--with-readline=/fake/readline",
        "--with-bz2=/fake/bzip2",
        "--with-iconv=/fake/libiconv",
        "--with-gmp=/fake/gmp",
    }) do
        assert(set[flag], version .. " lacks " .. flag)
    end
    -- libedit takes its directory until PHP 7.3, and the flag alone from PHP 7.4.
    local libedit = LIBEDIT_FLAG[version]
    assert(libedit ~= nil, version .. " has no libedit flag in the test")
    local other = libedit == "--with-libedit" and "--with-libedit=/fake/libedit" or "--with-libedit"
    assert(set[libedit], version .. " lacks " .. libedit)
    assert(not set[other], version .. " must not take " .. other)
end
print("macOS formulae follow the PHP version")

-- 4. Without Homebrew, the build stops, and a formula that is missing is left out.
RUNTIME.osType = "darwin"
fresh({ brew = false })
fails(function()
    configure_of("8.5.12")
end, "ERROR: Please install homebrew for OSX")
fresh({ brew = true, formulae = { ["openssl@1.1"] = "/fake/openssl@1.1" } })
fails(function()
    configure_of("8.5.12")
end, "PHP 8.5.12 requires openssl@3; install a compatible dependency before building.")
print("macOS stops without Homebrew or without the OpenSSL that PHP needs")

-- 5. PHP_CONFIGURE_OPTIONS replaces the platform options, and the global options stay.
RUNTIME.osType = "linux"
fresh({ env = { HOME = "/home/user", PHP_CONFIGURE_OPTIONS = "--with-openssl=/custom/openssl --with-curl" } })
local set, args = configure_of("8.5.12")
assert(args[1] == "--with-openssl=/custom/openssl" and args[2] == "--with-curl", table.concat(args, " "))
assert(not set["--with-gmp"], "the platform options are replaced, so gmp is not added")
assert(set["--enable-bcmath"] and set["--with-mhash"], "the global options stay")
assert(#H.commands == 0, "the libraries are not probed when the options are given")
print("PHP_CONFIGURE_OPTIONS replaces the platform options")

-- 6. PEAR, PCRE JIT and ZTS. PHP 5.x has no --without-pcre-jit, and PHP 5.x and 7.x take
-- --enable-maintainer-zts.
fresh({ env = { HOME = "/home/user", PHP_WITHOUT_PEAR = "yes", PHP_WITHOUT_PCRE_JIT = "yes" } })
set = configure_of("8.5.12")
assert(set["--without-pear"] and not set["--with-pear"], "PHP_WITHOUT_PEAR builds without PEAR")
assert(set["--without-pcre-jit"], "PHP_WITHOUT_PCRE_JIT builds without PCRE JIT")
set = configure_of("5.6.40")
assert(not set["--without-pcre-jit"], "PHP 5.x does not take --without-pcre-jit")
fresh()
local _, nts = configure_of("8.4.5")
assert(not mentions(nts, "zts"), "an NTS build takes no ZTS option")
local _, zts8 = configure_of("8.4.5", true)
assert(zts8[#zts8] == "--enable-zts", "PHP 8.x takes --enable-zts: " .. zts8[#zts8])
local _, zts7 = configure_of("7.4.33", true)
assert(zts7[#zts7] == "--enable-maintainer-zts", "PHP 7.x takes --enable-maintainer-zts")
local _, zts5 = configure_of("5.6.40", true)
assert(zts5[#zts5] == "--enable-maintainer-zts", "PHP 5.x takes --enable-maintainer-zts")
local _, pear_last = configure_of("8.5.12")
assert(pear_last[#pear_last] == "--with-pear", "PEAR comes after the global options: " .. pear_last[#pear_last])
print("PEAR, PCRE JIT and ZTS follow the switches and the version")

-- 7. Libraries that are missing are reported, and their options are left out.
fresh({ libraries = "libsodium.so.23 => /lib/libsodium.so.23\n", headers = set_of({ "sodium.h" }) })
set = configure_of("8.5.12")
assert(not set["--with-gmp"], "gmp is absent when its library is")
assert(mentions(H.notices, "gmp not found, not including in installation"), table.concat(H.notices, "|"))
assert(set["--with-sodium"], "sodium is present when its library and header are")
fresh({ libraries = "libgmp.so.10 => /lib/libgmp.so.10\n", headers = set_of({ "gmp.h" }) })
set = configure_of("8.5.12")
assert(not set["--with-sodium"] and mentions(H.notices, "sodium not found"), table.concat(H.notices, "|"))
fresh({ libraries = "", headers = set_of({}) })
set, _ = configure_of("7.1.33")
assert(not mentions(H.notices, "sodium"), "sodium is not reported for a PHP that does not take it")
print("missing gmp and sodium are reported and left out")

-- 8. The Linux build dependencies: what is missing, and the packages that provide them.
fresh()
local missing, packages = php_build.missing_dependencies(false)
assert(#missing == 0 and #packages == 0, "a full Linux has every dependency")
fresh({ tools = set_of({ "make", "pkg-config", "curl" }) })
missing, packages = php_build.missing_dependencies(false)
assert(#missing == 2 and missing[1].name == "cc" and missing[2].name == "autoconf", #missing)
assert(missing[1].need == "a C compiler" and missing[2].need == "buildconf", missing[1].need)
assert(#packages == 2 and packages[1] == "build-essential" and packages[2] == "autoconf", table.concat(packages, " "))
-- Two tools from one package are reported with one package.
fresh({ tools = set_of({ "autoconf", "pkg-config", "curl" }) })
missing, packages = php_build.missing_dependencies(false)
assert(#missing == 2 and #packages == 1 and packages[1] == "build-essential", table.concat(packages, " "))
-- With PHP_CONFIGURE_OPTIONS set, the headers and libxslt of the platform options are not needed.
fresh({
    headers = set_of({}),
    pkgs = set_of({
        "zlib",
        "libxml-2.0",
        "libcurl",
        "gdlib",
        "libpng",
        "libzip",
        "icu-uc",
        "icu-io",
        "icu-i18n",
        "oniguruma",
        "sqlite3",
    }),
})
missing = php_build.missing_dependencies(false)
assert(#missing == 4, "the platform headers and libxslt are needed without PHP_CONFIGURE_OPTIONS: " .. #missing)
missing = php_build.missing_dependencies(true)
assert(#missing == 0, "they are not needed when PHP_CONFIGURE_OPTIONS is set: " .. #missing)
print("Linux build dependencies are checked, and reported with their packages")

-- 9. The directory that PHP is built in for an install path with a space.
fresh({ env = { HOME = "/home/user" } })
assert(php_build.build_base() == "/home/user/.local/share/vfox-php", php_build.build_base())
fresh({ env = { HOME = "/home/user", XDG_DATA_HOME = "/home/user/xdg" } })
assert(php_build.build_base() == "/home/user/xdg/vfox-php", php_build.build_base())
fresh({ env = { HOME = "/home/user", XDG_DATA_HOME = "/home/user/xdg data" } })
assert(php_build.build_base() == "/home/user/.local/share/vfox-php", "a space in XDG_DATA_HOME is skipped")
fresh({ env = { HOME = "/home/John Doe" } })
assert(php_build.build_base() == "/var/tmp/vfox-php-1000", "a space in HOME is skipped: " .. php_build.build_base())
fresh({ env = { HOME = "/home/user" } })
assert(
    php_build.build_dir_for("/home/John Doe/.vfox/sdks/php-8.5.12") == "/home/user/.local/share/vfox-php/builds/4242",
    php_build.build_dir_for("/home/John Doe/.vfox/sdks/php-8.5.12")
)
print("the build directory has no space and is named by the install path")

-- 10. A plain install path: the dependencies are checked first, then the source is moved,
-- compiled, given its php.ini and Composer, and the source is removed.
RUNTIME.osType = "linux"
local plain = "/home/user/.vfox/sdks/php-8.5.12"
fresh({ existing = { [plain .. "_source"] = true } })
php_build.install(plain, "8.5.12", false)
assert(#H.moves == 1 and H.moves[1][1] == plain and H.moves[1][2] == plain .. "_source", "the source is moved")
assert(next(H.links) == nil, "a plain install path is built in place, with no link")
local build = build_commands()
assert(#build == 4, "buildconf, configure, make and make install: " .. #build)
assert(string.find(build[1], "./buildconf --force", 1, true), build[1])
assert(string.find(build[2], "./configure '--with-openssl'", 1, true), build[2])
assert(string.find(build[2], "'--prefix=" .. plain .. "'", 1, true), "configure is given the install path")
assert(string.find(build[3], "&& make", 1, true) and string.find(build[4], "&& make install", 1, true))
assert(
    H.files[plain .. "/conf.d/php.ini"] == "# add system-wide php configuration options here\n",
    "the php.ini is written"
)
assert(H.dirs[plain .. "/conf.d"], "conf.d is made")
assert(contains(H.removed, plain .. "_source"), "the source is removed after the build")
assert(contains(H.removed, plain .. "/bin/composer-setup.php"), "the installer is removed")
assert(mentions(H.commands, "--install-dir='" .. plain .. "/bin' --filename=composer"), "composer is installed")
assert(contains(H.urls, "https://getcomposer.org/installer"), "the installer is downloaded")
assert(contains(H.urls, "https://composer.github.io/installer.sig"), "the signature is downloaded")
assert(mentions(H.commands, "ABCDEF"), "the signature, trimmed, is compared with the installer's hash")
print("a plain install path is checked, compiled, and given php.ini and Composer")

-- 11. An install path with a space is built in the build directory, and linked to it.
local spaced = "/home/John Doe/.vfox/sdks/php-8.5.12"
local build_dir = "/home/user/.local/share/vfox-php/builds/4242"
fresh({ existing = { [build_dir .. ".source"] = true } })
php_build.install(spaced, "8.5.12", false)
assert(H.dirs["/home/user/.local/share/vfox-php/builds"], "the parent of the build directory is made")
assert(H.moves[1][1] == spaced and H.moves[1][2] == build_dir .. ".source", "the source moves to the build's source")
assert(H.links[spaced] == build_dir, "the install path links to the build directory")
assert(mentions(build_commands(), "--prefix=" .. build_dir), "configure builds into the build directory")
assert(H.files[spaced .. "/conf.d/php.ini"] ~= nil, "php.ini goes through the link")
assert(contains(H.removed, build_dir .. ".source"), "the source is removed after the build")
print("an install path with a space is built outside it, and linked")

-- 12. A failed build removes what it made when the path has a space, and nothing more when
-- it does not.
fresh({ fail = { "./configure" }, existing = { [build_dir] = true, [build_dir .. ".source"] = true } })
fails(function()
    php_build.install(spaced, "8.5.12", false)
end, "Compilation Failure")
assert(H.links[spaced] == nil or contains(H.removed, spaced), "the link at the install path is removed")
assert(contains(H.removed, build_dir), "the build directory is removed")
assert(contains(H.removed, build_dir .. ".source"), "the source directory is removed")
fresh({ fail = { "./configure" }, existing = { [plain .. "_source"] = true } })
fails(function()
    php_build.install(plain, "8.5.12", false)
end, "Compilation Failure")
assert(not contains(H.removed, plain .. "_source"), "a plain path keeps its source, as before")
print("a failed build with a space removes its build, and a plain one keeps its source")

-- 13. Composer: an installer that does not match the published sha384 is removed, and
-- the install stops. A signature that cannot be fetched stops it too.
fresh({ sha_ok = false, existing = { [plain .. "_source"] = true } })
fails(function()
    php_build.install(plain, "8.5.12", false)
end, "does not match the sha384")
assert(contains(H.removed, plain .. "/bin/composer-setup.php"), "the mismatched installer is removed")
assert(not mentions(H.commands, "--install-dir="), "composer is not installed after a mismatch")
fresh({
    http = { ["https://composer.github.io/installer.sig"] = { status_code = 503, body = "" } },
    existing = { [plain .. "_source"] = true },
})
fails(function()
    php_build.install(plain, "8.5.12", false)
end, "HTTP 503")
print("Composer refuses an installer that does not match its published sha384")

-- 14. Missing dependencies stop the install before anything is moved or compiled.
fresh({ tools = set_of({ "make", "pkg-config", "curl" }) })
local message = fails(function()
    php_build.install(plain, "8.5.12", false)
end, "ERROR: PHP cannot be built")
assert(message:find("  - cc: a C compiler", 1, true), message)
assert(message:find("sudo apt-get install --assume-yes build-essential autoconf", 1, true), message)
assert(#H.moves == 0 and #build_commands() == 0, "nothing is moved or compiled")
print("missing build dependencies stop the install before anything is compiled")

-- 15. Removing the build of an install path with a space: only the build directory a link
-- points to is removed.
fresh({ links = { [spaced] = build_dir }, existing = { [build_dir] = true } })
php_build.remove_build(spaced)
assert(contains(H.removed, build_dir), "the build directory is removed")
fresh({ links = { [spaced] = "/tmp/elsewhere" } })
message = fails(function()
    php_build.remove_build(spaced)
end, "is not a vfox-php build directory")
assert(#H.removed == 0, "nothing is removed for another directory")
fresh()
php_build.remove_build(plain)
assert(#H.removed == 0 and #H.commands > 0, "a path that is not a link is left alone")
print("remove_build removes only the build a link points to")

-- 16. macOS: the environment of the build puts bison first on PATH, and the pkg-config
-- directories first on PKG_CONFIG_PATH, in the order of the formulae.
RUNTIME.osType = "darwin"
local mac = "/Users/u/.vfox/sdks/php-8.5.12"
fresh({
    brew = true,
    env = { HOME = "/Users/u", PATH = "/usr/bin:/bin", PKG_CONFIG_PATH = "/x/pkg" },
    formulae = {
        bison = "/opt/homebrew/opt/bison",
        icu4c = "/opt/homebrew/opt/icu4c",
        libxslt = "/opt/homebrew/opt/libxslt",
        ["openssl@3"] = "/opt/homebrew/opt/openssl@3",
        gmp = "/opt/homebrew/opt/gmp",
        libsodium = "/opt/homebrew/opt/libsodium",
        readline = "/opt/homebrew/opt/readline",
        gettext = "/opt/homebrew/opt/gettext",
        libxml2 = "/opt/homebrew/opt/libxml2",
        zlib = "/opt/homebrew/opt/zlib",
        libedit = "/opt/homebrew/opt/libedit",
        bzip2 = "/opt/homebrew/opt/bzip2",
        libiconv = "/opt/homebrew/opt/libiconv",
    },
    existing = { [mac .. "_source"] = true },
})
php_build.install(mac, "8.5.12", false)
local configure = build_commands()[2]
assert(
    string.find(
        configure,
        "export PATH='/opt/homebrew/opt/bison/bin:/usr/bin:/bin'; export PKG_CONFIG_PATH='/opt/homebrew/opt/openssl@3/lib/pkgconfig:/opt/homebrew/opt/libxslt/lib/pkgconfig:/opt/homebrew/opt/libxml2/lib/pkgconfig:/opt/homebrew/opt/libedit/lib/pkgconfig:/opt/homebrew/opt/icu4c/lib/pkgconfig:/x/pkg'; ./configure",
        1,
        true
    ),
    configure
)
assert(string.find(configure, "'--with-openssl=/opt/homebrew/opt/openssl@3'", 1, true), configure)
assert(build_commands()[1]:find("export PATH=", 1, true), "every build step gets the environment")
print("macOS builds with bison first and the formulae's pkg-config directories")

-- 17. macOS without Homebrew: the install stops before anything is moved.
fresh({ brew = false, existing = { [mac .. "_source"] = true } })
fails(function()
    php_build.install(mac, "8.5.12", false)
end, "ERROR: Please install homebrew for OSX")
assert(#H.moves == 0, "nothing is moved without Homebrew")
RUNTIME.osType = "linux"
print("macOS install stops without Homebrew")

-- 18. The dependencies that are checked on Linux are run with the commands of the machine.
fresh()
php_build.missing_dependencies(false)
assert(mentions(H.commands, "'cc' --version >/dev/null 2>&1"), "the compiler is probed")
assert(
    mentions(H.commands, "pkg-config --exists 'icu-uc' 'icu-io' 'icu-i18n' >/dev/null 2>&1"),
    "the ICU modules are probed together"
)
print("the probes run the commands that check the machine")

print("php_build unit tests passed")
