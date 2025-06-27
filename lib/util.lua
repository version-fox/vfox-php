local util = {}

function util.starts_with(str, prefix)
    return str:sub(1, string.len(prefix)) == prefix
end

function util.ends_with(str, suffix)
    return str:sub(-string.len(suffix)) == suffix
end

function util.split_string(str, delimiter)
    local result = {}
    for substr in str:gmatch('([^' .. delimiter .. ']+)') do
        table.insert(result, substr)
    end
    return result
end

function util.compare_versions(v1, v2)
    local v1_parts = {}
    for part in string.gmatch(v1, '[^.]+') do
        table.insert(v1_parts, tonumber(part))
    end

    local v2_parts = {}
    for part in string.gmatch(v2, '[^.]+') do
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
    return util.starts_with(version, 'php')
        and not util.starts_with(version, 'php-debug')
        and not util.starts_with(version, 'php-devel')
        and not util.starts_with(version, 'php-test')
        and not string.find(version, 'src')
        and util.ends_with(version, '.zip')
        and ((RUNTIME.archType == '386' and string.find(version, 'x86'))
            or (RUNTIME.archType ~= '386' and string.find(version, 'x64')))
end

function util.read_file(filename)
    local file = io.open(filename, 'r')
    if not file then
        return '', 'Failed to open file: ' .. filename
    end
    local content = file:read('*a')
    file:close()
    return content
end

function util.write_file(filename, content)
    local file = io.open(filename, 'w')
    if not file then
        return false, 'Failed to open file for writing: ' .. filename
    end
    file:write(content)
    file:close()
    return true
end

return util
