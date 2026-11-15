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

package.path = "./lib/?.lua;" .. package.path
PLUGIN = {}
RUNTIME = { osType = "windows" }
local state = { files = {}, commands = {} }
local util = require("util")
util.read_file = function()
    return ';extension_dir = "ext"\n;extension=openssl\n;extension=php_openssl.dll\n'
end
util.write_file = function(path, content)
    state.files[path] = content
    return true
end
package.preload.http = function()
    return {
        get = function()
            return { status_code = 200, body = "composer installer" }
        end,
    }
end
os.execute = function(command)
    state.commands[#state.commands + 1] = command
    return 0
end
os.remove = function() end
dofile("hooks/post_install.lua")
local path = "C:\\SDKs\\100% PHP"
PLUGIN:PostInstall({ sdkInfo = { php = { path = path, version = "8.4.2" } } })
local ini = assert(state.files[path .. "\\php.ini"])
assert(ini:find('extension_dir = "C:/SDKs/100% PHP/ext"', 1, true), ini)
assert(ini:find("\nextension=openssl\n", 1, true), ini)
assert(ini:find("\nextension=php_openssl.dll\n", 1, true), ini)
assert(#state.commands == 1)
print("Windows PHP extension path substitution passed")
