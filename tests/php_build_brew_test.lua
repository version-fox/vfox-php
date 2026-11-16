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

-- The configure options of a macOS build, checked against the Homebrew of the Mac that runs
-- the test. Nothing is faked here: the real uname and brew answer. On any other system, and
-- on a Mac without Homebrew, the test does nothing.
package.path = "./lib/?.lua;" .. package.path
PLUGIN = {}
RUNTIME = { osType = "darwin" }
package.preload.http = function()
    return {}
end

local function output_of(command)
    local handle = io.popen(command, "r")
    if handle == nil then
        return ""
    end
    local text = handle:read("*a") or ""
    handle:close()
    return (string.gsub(text, "%s+$", ""))
end

if output_of("uname -s") ~= "Darwin" then
    print("macOS Homebrew options: skipped, this is not a Mac")
    return
end
if output_of("brew --version 2>/dev/null") == "" then
    print("macOS Homebrew options: skipped, Homebrew is not installed")
    return
end

-- The prefix of a formula that Homebrew has installed, or nil, as the build asks for it.
local function brew_prefix(formula)
    if output_of("brew ls --versions '" .. formula .. "' 2>/dev/null") == "" then
        return nil
    end
    return output_of("brew --prefix '" .. formula .. "' 2>/dev/null")
end

local php_build = require("php_build")
local args = php_build.configure_arguments("/tmp/php-host", "8.5.12", false)

local function taken_with(flag)
    for _, arg in ipairs(args) do
        if arg == flag or arg:sub(1, #flag + 1) == flag .. "=" then
            return arg
        end
    end
    return nil
end

-- PHP 8.5 takes these formulae: an installed one gives its prefix, and a missing one gives no
-- argument.
local TAKEN = {
    { "bzip2", "--with-bz2" },
    { "gettext", "--with-gettext" },
    { "libedit", "--with-libedit" },
    { "libiconv", "--with-iconv" },
    { "libxslt", "--with-xsl" },
    { "readline", "--with-readline" },
    { "gmp", "--with-gmp" },
    { "libsodium", "--with-sodium" },
}
for _, item in ipairs(TAKEN) do
    local prefix = brew_prefix(item[1])
    local got = taken_with(item[2])
    if prefix then
        assert(
            got == item[2] .. "=" .. prefix,
            item[1] .. ": want " .. item[2] .. "=" .. prefix .. ", got " .. tostring(got)
        )
    else
        assert(got == nil, item[1] .. " is not installed, yet " .. tostring(got) .. " is there")
    end
end

-- OpenSSL 3 is what PHP 8.5 builds against, and the build stops without it.
local openssl = brew_prefix("openssl@3")
assert(openssl ~= nil, "install openssl@3 with Homebrew")
assert(taken_with("--with-openssl") == "--with-openssl=" .. openssl, tostring(taken_with("--with-openssl")))

-- PHP 8.5 does not take these formulae, so no argument may name them.
for _, flag in ipairs({
    "--with-freetype-dir",
    "--with-icu-dir",
    "--with-jpeg-dir",
    "--with-webp-dir",
    "--with-png-dir",
    "--with-libxml-dir",
    "--with-zlib-dir",
    "--with-libzip",
}) do
    assert(taken_with(flag) == nil, "PHP 8.5 does not take " .. flag .. ": " .. tostring(taken_with(flag)))
end

print("macOS Homebrew options follow the installed formulae")
