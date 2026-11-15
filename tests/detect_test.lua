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

-- The Detect hook: which PHP installs are found, how they are named, and which
-- are left alone. The file system, the PATH and the commands that probe a PHP are
-- faked, so this runs on any host.
package.path = "./lib/?.lua;" .. package.path
PLUGIN = {}
RUNTIME = { osType = "linux", pluginDirPath = "/home/test/.version-fox/plugin/php" }
local detect = require("detect_php")

-- The fakes and the test share these tables, and only their fields change: the
-- Lua runtime used here does not see a local that a function has rebound.
local S = { env = {}, files = {}, dirs = {}, which = {}, probes = {} }

-- Paths are compared with forward slashes, so that Windows paths can be written
-- with backslashes in the test.
local function norm(path)
    return (path:gsub("\\", "/"))
end

os.getenv = function(name)
    return S.env[name]
end

io.open = function(path)
    if S.files[norm(path)] then
        return {
            close = function()
                return true
            end,
        }
    end
    return nil
end

-- Answers the commands detect_php runs: the PATH lookup, the directory listings,
-- and `php -v` for the PHP executables.
io.popen = function(command)
    local lines = {}
    if command:find("command -v php", 1, true) or command:find("where php", 1, true) then
        lines = S.which
    elseif command:match("^ls %-1 '(.-)'") then
        lines = S.dirs[norm(command:match("^ls %-1 '(.-)'"))] or {}
    elseif command:match('^dir /b /ad "(.-)"') then
        lines = S.dirs[norm(command:match('^dir /b /ad "(.-)"'))] or {}
    else
        local exe = command:match("^'(.-)' %-v") or command:match('^""(.-)" %-v')
        if exe then
            lines = S.probes[norm(exe)] or {}
        end
    end
    -- Like vfox's io.popen on Windows, the handle has read and close, and no lines:
    -- a command's output is read whole.
    local output = ""
    if #lines > 0 then
        output = table.concat(lines, "\n") .. "\n"
    end
    local consumed = false
    return {
        read = function(_, format)
            assert(format == "*a", "the whole output is read: " .. tostring(format))
            if consumed then
                return ""
            end
            consumed = true
            return output
        end,
        close = function()
            return true
        end,
    }
end

local function scene(opts)
    RUNTIME.osType = opts.os
    RUNTIME.pluginDirPath = opts.pluginDirPath or "/home/test/.version-fox/plugin/php"
    S.env = opts.env or {}
    S.files, S.dirs, S.which, S.probes = {}, {}, opts.which or {}, {}
    for _, path in ipairs(opts.files or {}) do
        S.files[norm(path)] = true
    end
    for dir, names in pairs(opts.dirs or {}) do
        S.dirs[norm(dir)] = names
    end
    for exe, lines in pairs(opts.probes or {}) do
        S.probes[norm(exe)] = lines
    end
end

local function expect_count(list, want)
    assert(#list == want, string.format("found %d installs, want %d", #list, want))
end

local function expect_found(list, version, path, note)
    local hit
    for _, item in ipairs(list) do
        if item.version == version then
            hit = item
        end
    end
    assert(hit ~= nil, "no install named " .. version)
    assert(hit.path == path, version .. " is at " .. tostring(hit.path) .. ", want " .. path)
    assert(hit.note == note, version .. " has note " .. tostring(hit.note) .. ", want " .. note)
end

-- Names follow the plugin's own: an NTS build on Windows and a ZTS build elsewhere
-- carry a suffix, the other kind has none.
RUNTIME.osType = "linux"
assert(detect.version_name({ version = "8.4.5", ts = "NTS" }) == "8.4.5")
assert(detect.version_name({ version = "8.4.5", ts = "ZTS" }) == "8.4.5-zts")
assert(detect.version_name({ version = "8.4.5" }) == "8.4.5")
RUNTIME.osType = "windows"
assert(detect.version_name({ version = "8.4.5", ts = "NTS" }) == "8.4.5-nts")
assert(detect.version_name({ version = "8.4.5", ts = "ZTS" }) == "8.4.5")
RUNTIME.osType = "linux"
print("version names follow the plugin's own names")

-- Homebrew kegs: php and php@X.Y are installs, and the other kegs are not probed.
scene({
    os = "darwin",
    env = { HOME = "/Users/test" },
    dirs = { ["/opt/homebrew/opt"] = { "openssl", "php", "php@8.3" } },
    files = {
        "/opt/homebrew/opt/php/bin/php",
        "/opt/homebrew/opt/php@8.3/bin/php",
    },
    probes = {
        ["/opt/homebrew/opt/php/bin/php"] = { "PHP 8.5.12 (cli) (built: Nov 10 2026 10:00:00) (NTS)" },
        ["/opt/homebrew/opt/php@8.3/bin/php"] = { "PHP 8.3.6 (cli) (built: Mar 1 2026 10:00:00) (NTS)" },
    },
})
local list = detect.find_all()
expect_count(list, 2)
expect_found(list, "8.3.6", "/opt/homebrew/opt/php@8.3", "installed by Homebrew")
expect_found(list, "8.5.12", "/opt/homebrew/opt/php", "installed by Homebrew")
print("Homebrew kegs on macOS are found by their php and php@X.Y names")

-- A PHP under /opt is an install when its folder name starts with php, and a
-- ZTS build on Linux is named with -zts.
scene({
    os = "linux",
    env = { HOME = "/home/test" },
    dirs = { ["/opt"] = { "notes", "php-8.4" } },
    files = { "/opt/php-8.4/bin/php", "/opt/notes/bin/php" },
    probes = {
        ["/opt/php-8.4/bin/php"] = { "PHP 8.4.5 (cli) (built: Jan 1 2026 10:00:00) (ZTS)" },
        ["/opt/notes/bin/php"] = { "PHP 9.0.0 (cli) (built: Jan 1 2026 10:00:00) (NTS)" },
    },
})
list = detect.find_all()
expect_count(list, 1)
expect_found(list, "8.4.5-zts", "/opt/php-8.4", "installed under /opt")
print("a php folder under /opt is found, and a ZTS build is named with -zts")

-- The PHP that the PATH names under a shared directory is not linked: /usr would
-- link the whole system.
scene({
    os = "linux",
    env = { HOME = "/home/test" },
    which = { "/usr/bin/php" },
    files = { "/usr/bin/php" },
    probes = { ["/usr/bin/php"] = { "PHP 8.3.6 (cli) (built: Mar 1 2026 10:00:00) (NTS)" } },
})
expect_count(detect.find_all(), 0)
print("a PHP under a shared system directory is not linked")

-- The PHP that the PATH names in a folder of its own is found.
scene({
    os = "linux",
    env = { HOME = "/home/test" },
    which = { "/srv/php-custom/bin/php" },
    files = { "/srv/php-custom/bin/php" },
    probes = { ["/srv/php-custom/bin/php"] = { "PHP 8.2.28 (cli) (built: Mar 1 2026 10:00:00) (NTS)" } },
})
list = detect.find_all()
expect_count(list, 1)
expect_found(list, "8.2.28", "/srv/php-custom", "on PATH")
print("a PHP on the PATH in its own folder is found")

-- The hook returns what find_all finds.
scene({
    os = "linux",
    env = { HOME = "/home/test" },
    which = { "/srv/php-custom/bin/php" },
    files = { "/srv/php-custom/bin/php" },
    probes = { ["/srv/php-custom/bin/php"] = { "PHP 8.2.28 (cli) (built: Mar 1 2026 10:00:00) (NTS)" } },
})
dofile("hooks/detect.lua")
expect_count(PLUGIN:Detect({}), 1)
print("the Detect hook returns the installs")

-- Installs that vfox manages are never reported: those under VFOX_HOME, and those
-- under a .vfox folder of a project.
scene({
    os = "linux",
    env = { HOME = "/home/test", VFOX_HOME = "/home/test/.version-fox" },
    which = {
        "/home/test/.version-fox/cache/php/v-8.5.12/php-8.5.12/bin/php",
        "/home/test/project/.vfox/sdks/php/bin/php",
    },
    files = {
        "/home/test/.version-fox/cache/php/v-8.5.12/php-8.5.12/bin/php",
        "/home/test/project/.vfox/sdks/php/bin/php",
    },
    probes = {
        ["/home/test/.version-fox/cache/php/v-8.5.12/php-8.5.12/bin/php"] = { "PHP 8.5.12 (cli) (NTS)" },
        ["/home/test/project/.vfox/sdks/php/bin/php"] = { "PHP 8.5.12 (cli) (NTS)" },
    },
})
expect_count(detect.find_all(), 0)
print("installs that vfox manages are not reported")

-- Scoop keeps each version in its own folder, and current is a link to one of
-- them: the version is reported once, with the first path.
scene({
    os = "windows",
    env = { USERPROFILE = "C:\\Users\\test" },
    dirs = { ["C:\\Users\\test\\scoop\\apps\\php"] = { "8.4.5", "current" } },
    files = {
        "C:\\Users\\test\\scoop\\apps\\php\\8.4.5\\php.exe",
        "C:\\Users\\test\\scoop\\apps\\php\\current\\php.exe",
    },
    probes = {
        ["C:\\Users\\test\\scoop\\apps\\php\\8.4.5\\php.exe"] = {
            "PHP 8.4.5 (cli) (built: Jan 1 2026 10:00:00) (NTS Visual C++ 2022 x64)",
        },
        ["C:\\Users\\test\\scoop\\apps\\php\\current\\php.exe"] = {
            "PHP 8.4.5 (cli) (built: Jan 1 2026 10:00:00) (NTS Visual C++ 2022 x64)",
        },
    },
})
list = detect.find_all()
expect_count(list, 1)
expect_found(list, "8.4.5-nts", "C:\\Users\\test\\scoop\\apps\\php\\8.4.5", "installed by Scoop")
print("Scoop apps are found, and a version is reported once")

-- The Scoop shims only forward to the install, so they are not linked.
scene({
    os = "windows",
    env = { USERPROFILE = "C:\\Users\\test" },
    which = { "C:\\Users\\test\\scoop\\shims\\php.exe" },
    files = { "C:\\Users\\test\\scoop\\shims\\php.exe" },
    probes = { ["C:\\Users\\test\\scoop\\shims\\php.exe"] = { "PHP 8.4.5 (cli) (NTS Visual C++ 2022 x64)" } },
})
expect_count(detect.find_all(), 0)
print("shims are not linked")

-- XAMPP keeps PHP at the root of its folder, and a TS build has no suffix on
-- Windows.
scene({
    os = "windows",
    env = { USERPROFILE = "C:\\Users\\test" },
    files = { "C:\\xampp\\php\\php.exe" },
    probes = {
        ["C:\\xampp\\php\\php.exe"] = { "PHP 8.3.6 (cli) (built: Mar 1 2026 10:00:00) (ZTS Visual C++ 2019 x64)" },
    },
})
list = detect.find_all()
expect_count(list, 1)
expect_found(list, "8.3.6", "C:\\xampp\\php", "installed by XAMPP")
print("XAMPP is found, and a TS build has no suffix on Windows")

-- A PHP that does not answer `php -v` is not an install.
scene({
    os = "windows",
    env = { USERPROFILE = "C:\\Users\\test" },
    files = { "C:\\php\\php.exe" },
    probes = {},
})
expect_count(detect.find_all(), 0)
print("a PHP that does not answer is not reported")

print("Detect hook tests passed")
