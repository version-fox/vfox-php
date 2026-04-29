--- !!! DO NOT EDIT OR RENAME !!!
PLUGIN = {}

--- !!! MUST BE SET !!!
--- Plugin name
PLUGIN.name = "php"
--- Plugin version
PLUGIN.version = "0.4.0"
--- Plugin homepage
PLUGIN.homepage = "https://github.com/version-fox/vfox-php"
--- Plugin license, please choose a correct license according to your needs.
PLUGIN.license = "Apache 2.0"
--- Plugin description
PLUGIN.description = "PHP plugin, https://www.php.net/"


--- !!! OPTIONAL !!!
--[[
NOTE:
    Minimum compatible vfox version.
    If the plugin is not compatible with the current vfox version,
    vfox will not load the plugin and prompt the user to upgrade vfox.
 --]]
PLUGIN.minRuntimeVersion = "0.5.1"
--[[
NOTE:
    If configured, vfox will check for updates to the plugin at this address,
    otherwise it will check for updates at the global registry.
 --]]
PLUGIN.manifestUrl = "https://github.com/version-fox/vfox-php/releases/download/manifest/manifest.json"
-- Some things that need user to be attention!
PLUGIN.notes = {
    "For macOS and Linux user:",
    "PHP installation requires some dependencies.",
    "For more detailed, please refer to https://github.com/version-fox/vfox-php/blob/main/README.md"
}
