package.path = "./lib/?.lua;" .. package.path
PLUGIN = {}
RUNTIME = { osType = "windows", archType = "amd64" }
local responses, state = {}, {}
package.preload.http = function()
    return {
        get = function(args)
            if state.failure then
                return state.failure.response, state.failure.error
            end
            return { status_code = 200, body = assert(responses[args.url], "unexpected URL " .. args.url) }
        end,
    }
end
package.preload.json = function()
    return {
        decode = function(body)
            return body
        end,
    }
end
package.preload.html = function()
    return {
        parse = function(body)
            return {
                find = function()
                    return {
                        each = function(_, fn)
                            for i, filename in ipairs(body) do
                                fn(i, {
                                    attr = function()
                                        return filename
                                    end,
                                    text = function()
                                        return filename
                                    end,
                                })
                            end
                        end,
                    }
                end,
            }
        end,
    }
end
local current = "https://windows.php.net/downloads/releases/"
local archives = current .. "archives/"
responses[current] = {
    "/downloads/releases/php-8.4.2-nts-Win32-vs17-x64.zip",
    "/downloads/releases/php-8.4.2-Win32-vs17-x64.zip",
    "/downloads/releases/php-8.4.2-Win32-vs17-x86.zip",
    "/downloads/releases/php-8.4.2-debug-pack-Win32-vs17-x64.zip",
}
responses[archives] = {
    "php-5.6.16-nts-Win32-VC11-x64.zip",
    "php-8.4.2-Win32-vs17-x64.zip",
    "php-8.3.15-Win32-vs16-x64.zip",
    "php-8.4.1-nts-Win32-vs17-x64.zip",
    "php-7.2.33-1-Win32-VC15-x64.zip",
    "php-7.2.33-Win32-VC15-x64.zip",
}
for _, major in ipairs({ 5, 7, 8 }) do
    responses["https://www.php.net/releases/index.php?json&max=10000&version=" .. major] = {}
end
responses["https://www.php.net/releases/index.php?json&max=10000&version=8"] = {
    ["8.4.2"] = { source = { { filename = "php-8.4.2.tar.gz", sha256 = string.rep("a", 64) } } },
    ["8.3.15"] = { source = { { filename = "php-8.3.15.tar.gz", sha256 = string.rep("b", 64) } } },
    ["8.5.0RC1"] = { source = { { filename = "php-8.5.0RC1.tar.gz" } } },
}
dofile("hooks/available.lua")
dofile("hooks/pre_install.lua")
local list = PLUGIN:Available({})
assert(list[1].version == "8.4.2", "latest must be current TS, got " .. tostring(list[1].version))
assert(#list == 6, #list)
assert(PLUGIN:PreInstall({ version = "7.2.33" }).url == archives .. "php-7.2.33-1-Win32-VC15-x64.zip")
assert(PLUGIN:PreInstall({ version = "latest" }).url == current .. "php-8.4.2-Win32-vs17-x64.zip")
assert(PLUGIN:PreInstall({ version = "8.4.2-nts" }).version == "8.4.2-nts")
assert(PLUGIN:PreInstall({ version = "8.3" }).url == archives .. "php-8.3.15-Win32-vs16-x64.zip")
RUNTIME.archType = "386"
assert(#PLUGIN:Available({}) == 1)
RUNTIME.osType = "linux"
list = PLUGIN:Available({})
assert(#list == 2 and list[1].version == "8.4.2")
local install = PLUGIN:PreInstall({ version = "8.4" })
assert(install.url == "https://www.php.net/distributions/php-8.4.2.tar.gz")
assert(install.sha256 == string.rep("a", 64))
local function fails(fn, expected)
    local ok, err = pcall(fn)
    assert(not ok and tostring(err):find(expected, 1, true), tostring(err))
end
state.failure = { error = "timeout" }
fails(function()
    PLUGIN:Available({})
end, "timeout")
state.failure = { response = { status_code = 503 } }
fails(function()
    PLUGIN:PreInstall({ version = "latest" })
end, "503")
state.failure = nil
fails(function()
    PLUGIN:PreInstall({ version = "99.0.0" })
end, "not found")
print("PHP release discovery, ordering, architecture and failure cases passed")
