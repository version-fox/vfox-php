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

local util = {}

function util.starts_with(str, prefix)
    return str:sub(1, string.len(prefix)) == prefix
end

function util.ends_with(str, suffix)
    return str:sub(-string.len(suffix)) == suffix
end

function util.split_string(str, delimiter)
    local result = {}
    for substr in str:gmatch("([^" .. delimiter .. "]+)") do
        table.insert(result, substr)
    end
    return result
end

function util.compare_versions(v1, v2)
    local v1_parts = {}
    for part in string.gmatch(v1, "[^.]+") do
        table.insert(v1_parts, tonumber(part))
    end

    local v2_parts = {}
    for part in string.gmatch(v2, "[^.]+") do
        table.insert(v2_parts, tonumber(part))
    end

    for i = 1, math.max(#v1_parts, #v2_parts) do
        local v1_part = v1_parts[i] or 0
        local v2_part = v2_parts[i] or 0
        if v1_part > v2_part then
            return 1
        elseif v1_part < v2_part then
            return -1
        end
    end

    return 0
end

function util.filter_windows_version(version)
    return util.starts_with(version, "php")
        and not util.starts_with(version, "php-debug")
        and not util.starts_with(version, "php-devel")
        and not util.starts_with(version, "php-test")
        and not string.find(version, "src")
        and util.ends_with(version, ".zip")
        and (
            (RUNTIME.archType == "386" and string.find(version, "x86"))
            or (RUNTIME.archType ~= "386" and string.find(version, "x64"))
        )
end

function util.read_file(filename)
    local file = io.open(filename, "r")
    if not file then
        return "", "Failed to open file: " .. filename
    end
    local content = file:read("*a")
    file:close()
    return content
end

local function write(filename, content, mode)
    local file = io.open(filename, mode)
    if not file then
        return false, "Failed to open file for writing: " .. filename
    end
    file:write(content)
    file:close()
    return true
end

function util.write_file(filename, content)
    return write(filename, content, "w")
end

-- Writes the bytes as they are. A text-mode file on Windows turns every LF into CRLF,
-- which would damage an executable.
function util.write_binary_file(filename, content)
    return write(filename, content, "wb")
end

return util
