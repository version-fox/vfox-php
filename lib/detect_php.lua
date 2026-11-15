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

--- Finds the PHP installs that are already on the machine and that vfox did not
--- install, for `vfox link --detect php`. A version is named the way `vfox install`
--- names it: the PHP version, then -nts for an NTS build on Windows, where the
--- plugin installs TS builds without a suffix, and -zts for a ZTS build elsewhere,
--- where the plugin installs NTS builds without one.
local detect = {}

--- Whether the plugin runs on Windows, where PHP sits in its install root rather
--- than in bin.
local function is_windows()
    return RUNTIME ~= nil and RUNTIME.osType == "windows"
end

local function home_dir()
    return os.getenv("HOME") or os.getenv("USERPROFILE") or ""
end

local function sep()
    if is_windows() then
        return "\\"
    end
    return "/"
end

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Joins a directory and a name with the platform separator.
function detect.join(left, right)
    local last = left:sub(-1)
    if last == "/" or last == "\\" then
        return left .. right
    end
    return left .. sep() .. right
end

--- Returns the directory above path, or "" for a root.
local function parent(path)
    local trimmed = path:gsub("[/\\]+$", "")
    local index = trimmed:match(".*()[/\\]")
    if index == nil then
        return ""
    end
    if index == 1 then
        return trimmed:sub(1, 1)
    end
    if trimmed:sub(1, index - 1):match("^%a:$") then
        return trimmed:sub(1, index)
    end
    return trimmed:sub(1, index - 1)
end

--- Drops trailing separators, and on Windows lowercases the path and uses
--- backslashes, so that two spellings of one directory compare equal.
local function normalize(path)
    local value = path:gsub("[/\\]+$", "")
    if is_windows() then
        value = value:lower():gsub("/", "\\")
    end
    return value
end

--- Whether the normalized value holds name as one whole element of the path.
local function has_element(value, name)
    local s = sep()
    return value:find(s .. name .. s, 1, true) ~= nil or value:sub(-(#name + 1)) == s .. name
end

--- The base name of a path.
local function basename(path)
    return path:match("([^/\\]+)$") or path
end

--- Quotes one argument for io.popen: for cmd.exe on Windows, for sh elsewhere.
local function quote(value)
    if is_windows() then
        return '"' .. value:gsub('"', '""') .. '"'
    end
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

--- Runs a command and returns its lines, trimmed. A command that cannot run
--- returns none.
local function read_lines(command)
    local handle = io.popen(command, "r")
    if not handle then
        return {}
    end
    local lines = {}
    for line in handle:lines() do
        table.insert(lines, trim(line))
    end
    handle:close()
    return lines
end

--- Lists the immediate children of dir as full paths. Windows lists directories
--- only; elsewhere `ls` lists files too, and the caller probes what it finds.
local function children(dir)
    if dir == "" then
        return {}
    end
    local command
    if is_windows() then
        command = "dir /b /ad " .. quote(dir) .. " 2>nul"
    else
        command = "ls -1 " .. quote(dir) .. " 2>/dev/null"
    end
    local result = {}
    for _, name in ipairs(read_lines(command)) do
        if name ~= "" and name ~= "." and name ~= ".." then
            table.insert(result, detect.join(dir, name))
        end
    end
    return result
end

--- The PHP executable of a home: php.exe in the root on Windows, bin/php elsewhere.
--- Returns nil when there is none.
local function php_exe(home)
    local exe
    if is_windows() then
        exe = detect.join(home, "php.exe")
    else
        exe = detect.join(detect.join(home, "bin"), "php")
    end
    local file = io.open(exe, "rb")
    if file == nil then
        return nil
    end
    file:close()
    return exe
end

--- Reads the version and the thread-safety of a PHP from `php -v`. Its first
--- line reads "PHP 8.4.5 (cli) ..." and its build line names NTS or ZTS. Returns
--- nil for anything that does not answer that way, such as a broken install.
local function probe(home)
    local exe = php_exe(home)
    if exe == nil then
        return nil
    end
    local command
    if is_windows() then
        command = '""' .. exe .. '" -v 2>nul"'
    else
        command = quote(exe) .. " -v 2>/dev/null"
    end
    for _, line in ipairs(read_lines(command)) do
        local version = line:match("^PHP (%d+%.%d+%.%d+)")
        if version then
            return { version = version, ts = line:match("%(([NZ]TS)") }
        end
    end
    return nil
end

--- Names a probed PHP the way `vfox install` names it: an NTS build on Windows
--- and a ZTS build elsewhere carry a suffix, because the plugin installs the other
--- kind without one.
function detect.version_name(found)
    if is_windows() and found.ts == "NTS" then
        return found.version .. "-nts"
    end
    if not is_windows() and found.ts == "ZTS" then
        return found.version .. "-zts"
    end
    return found.version
end

--- The directories that hold PHP installs, and that no PHP install may be
--- linked as: linking one of them would link the whole system or a whole
--- package manager. Also the shims folders, which only forward to the install.
local function shared_dirs()
    local home = home_dir()
    if is_windows() then
        local userprofile = os.getenv("USERPROFILE") or home
        local programfiles = os.getenv("ProgramFiles") or "C:\\Program Files"
        local programfiles_x86 = os.getenv("ProgramFiles(x86)") or "C:\\Program Files (x86)"
        local programdata = os.getenv("ProgramData") or "C:\\ProgramData"
        return {
            "C:\\",
            "C:\\Windows",
            "C:\\tools",
            programfiles,
            programfiles_x86,
            programdata,
            userprofile,
            detect.join(userprofile, "scoop"),
        }
    end
    local dirs = { "/", "/usr", "/usr/local", "/opt", "/opt/homebrew", "/home/linuxbrew/.linuxbrew", "/Applications" }
    if home ~= "" then
        table.insert(dirs, home)
        table.insert(dirs, detect.join(home, ".local"))
        table.insert(dirs, detect.join(home, ".linuxbrew"))
        table.insert(dirs, detect.join(home, ".asdf"))
        table.insert(dirs, detect.join(home, ".phpenv"))
    end
    return dirs
end

--- Whether a home must never be linked: a shared directory, or a shims folder.
local function is_shared(path)
    local value = normalize(path)
    if value == "" or has_element(value, "shims") then
        return true
    end
    for _, dir in ipairs(shared_dirs()) do
        if normalize(dir) == value then
            return true
        end
    end
    return false
end

--- The VFOX_HOME, from the environment or from the plugin's own directory, which
--- lives at VFOX_HOME/plugin/php.
local function vfox_home()
    local home = os.getenv("VFOX_HOME")
    if home and home ~= "" then
        return home
    end
    if RUNTIME and RUNTIME.pluginDirPath and RUNTIME.pluginDirPath ~= "" then
        return parent(parent(RUNTIME.pluginDirPath))
    end
    return ""
end

--- Whether a home is one vfox manages, and so must never be reported: anything
--- under a .vfox directory, anything under VFOX_HOME, and the plugin's own builds.
local function is_vfox_managed(path)
    local value = normalize(path)
    if has_element(value, ".vfox") or value:find(sep() .. "vfox-php" .. sep() .. "builds" .. sep(), 1, true) then
        return true
    end
    local root = normalize(vfox_home())
    return root ~= "" and (value == root or value:sub(1, #root + 1) == root .. sep())
end

--- The install roots that the PATH names for php: the root of the PHP executable
--- on the PATH, which is the directory above bin, or the directory of php.exe.
local function on_path()
    local command
    if is_windows() then
        command = "where php 2>nul"
    else
        command = "command -v php 2>/dev/null"
    end
    local homes = {}
    for _, line in ipairs(read_lines(command)) do
        local absolute
        if is_windows() then
            absolute = line:match("^%a:[/\\]") ~= nil
        else
            absolute = line:sub(1, 1) == "/"
        end
        if absolute then
            if is_windows() then
                table.insert(homes, { path = parent(line) })
            else
                table.insert(homes, { path = parent(parent(line)) })
            end
        end
    end
    return homes
end

--- The places where PHP installs are kept. The mode says what a place holds:
---   home      a PHP install itself;
---   children  PHP installs, one per child folder;
---   php       a folder of programs, of which the children named php are installs;
---   brew      Homebrew's opt folder, of which php and php@X.Y are installs;
---   deep      a tool cache laid out as <php>/<version>/<arch>.
local function candidate_roots()
    local home = home_dir()
    local roots = {}
    local function add(path, note, mode)
        if path ~= nil and path ~= "" then
            table.insert(roots, { path = path, note = note, mode = mode })
        end
    end

    if is_windows() then
        local userprofile = os.getenv("USERPROFILE") or home
        local programfiles = os.getenv("ProgramFiles") or "C:\\Program Files"
        local programfiles_x86 = os.getenv("ProgramFiles(x86)")
        local programdata = os.getenv("ProgramData") or "C:\\ProgramData"
        add(detect.join(detect.join(userprofile, "scoop"), "apps\\php"), "installed by Scoop", "children")
        add("C:\\xampp\\php", "installed by XAMPP", "home")
        add("C:\\laragon\\bin\\php", "installed by Laragon", "children")
        add("C:\\wamp64\\bin\\php", "installed by WampServer", "children")
        add("C:\\wamp\\bin\\php", "installed by WampServer", "children")
        add("C:\\php", "installed by hand", "home")
        add("C:\\", "installed under C:\\", "php")
        add("C:\\tools", "installed by Chocolatey", "php")
        add(
            detect.join(detect.join(programdata, "chocolatey\\lib\\php"), "tools"),
            "installed by Chocolatey",
            "children"
        )
        add(detect.join(programfiles, "PHP"), "installed by hand", "children")
        if programfiles_x86 ~= nil and programfiles_x86 ~= "" then
            add(detect.join(programfiles_x86, "PHP"), "installed by hand", "children")
        end
        add("C:\\hostedtoolcache\\windows\\PHP", "CI runner tool cache", "deep")
        return roots
    end

    add("/opt/homebrew/opt", "installed by Homebrew", "brew")
    add("/usr/local/opt", "installed by Homebrew", "brew")
    add("/home/linuxbrew/.linuxbrew/opt", "installed by Homebrew", "brew")
    add("/opt", "installed under /opt", "php")
    add("/usr/local", "installed under /usr/local", "php")
    add("/opt/hostedtoolcache/PHP", "CI runner tool cache", "deep")
    if home ~= "" then
        add(detect.join(home, ".linuxbrew/opt"), "installed by Homebrew", "brew")
        add(detect.join(home, ".asdf/installs/php"), "installed by asdf", "children")
        add(detect.join(home, ".local/share/mise/installs/php"), "installed by mise", "children")
        add(detect.join(home, ".phpenv/versions"), "installed by phpenv", "children")
    end
    if RUNTIME and RUNTIME.osType == "darwin" then
        add("/Applications/MAMP/bin/php", "installed by MAMP", "children")
    end
    return roots
end

--- Finds every PHP install on the machine that vfox did not install. An install is
--- reported once per path, and once per version: the first path in order is kept,
--- as vfox links the first and skips the rest.
function detect.find_all()
    local found, seen = {}, {}

    local function consider(home, note)
        if home == "" or seen[home] or is_vfox_managed(home) or is_shared(home) then
            return
        end
        seen[home] = true
        local php = probe(home)
        if php then
            table.insert(found, { version = detect.version_name(php), path = home, note = note })
        end
    end

    for _, root in ipairs(candidate_roots()) do
        if root.mode == "home" then
            consider(root.path, root.note)
        elseif root.mode == "deep" then
            for _, version_dir in ipairs(children(root.path)) do
                consider(version_dir, root.note)
                for _, arch_dir in ipairs(children(version_dir)) do
                    consider(arch_dir, root.note)
                end
            end
        else
            for _, child in ipairs(children(root.path)) do
                local name = basename(child):lower()
                local matches = root.mode == "children"
                    or (root.mode == "php" and name:sub(1, 3) == "php")
                    or (root.mode == "brew" and (name == "php" or name:sub(1, 4) == "php@"))
                if matches then
                    consider(child, root.note)
                end
            end
        end
    end

    for _, entry in ipairs(on_path()) do
        consider(entry.path, "on PATH")
    end

    table.sort(found, function(a, b)
        if a.version ~= b.version then
            return a.version < b.version
        end
        return a.path < b.path
    end)
    local result, seen_versions = {}, {}
    for _, item in ipairs(found) do
        if not seen_versions[item.version] then
            seen_versions[item.version] = true
            table.insert(result, item)
        end
    end
    return result
end

return detect
