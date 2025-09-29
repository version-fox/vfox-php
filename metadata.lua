--- !!! DO NOT EDIT OR RENAME !!!
PLUGIN = {}

--- !!! MUST BE SET !!!
--- Plugin name
PLUGIN.name = "php"
--- Plugin version
PLUGIN.version = "0.3.0"
--- Plugin homepage
PLUGIN.homepage = "https://github.com/version-fox/vfox-php"
--- Plugin license, please choose a correct license according to your needs.
PLUGIN.license = "Apache 2.0"
--- Plugin description
PLUGIN.description = "php plugin"


--- !!! OPTIONAL !!!
--[[
NOTE:
    Minimum compatible vfox version.
    If the plugin is not compatible with the current vfox version,
    vfox will not load the plugin and prompt the user to upgrade vfox.
 --]]
PLUGIN.minRuntimeVersion = "0.3.2"
--[[
NOTE:
    If configured, vfox will check for updates to the plugin at this address,
    otherwise it will check for updates at the global registry.

    If you want use the global registry to distribute your plugin, you can remove this field.

    If you develop a plugin based on the template, which will automatically generate a manifest file by CI,
    you can set this address to the manifest file address, so that the plugin can be updated automatically.

 --]]
PLUGIN.manifestUrl = "https://github.com/version-fox/vfox-php/releases/download/manifest/manifest.json"
-- Some things that need user to be attention!
PLUGIN.notes = {
    "For macOS and Linux user:",
    "PHP installation requires some dependencies.",
    "For more detailed, please refer to https://github.com/version-fox/vfox-php/blob/main/README.md"
}
