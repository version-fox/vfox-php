# Install from source

[中文](zh-CN/install-from-source.md) | [English](install-from-source.md)

To try this repository before a release, install its checkout as a plugin. vfox takes a local archive with `vfox add -s`, and the archive has to hold the plugin at its root, with `metadata.lua` next to the folders.

```shell
git clone https://github.com/version-fox/vfox-php.git
cd vfox-php
zip -r ../php.zip ./
vfox add -s ../php.zip
vfox install php@latest
```

The archive is made outside the checkout, so `zip` does not pick itself up. The CI workflows make the same archive with `zip -r php.zip ./` at the repository root.

When you change the plugin, remove the old copy before you add the new archive:

```shell
vfox remove php
cd vfox-php
zip -r ../php.zip ./
vfox add -s ../php.zip
```

Requirements are the same as for the released plugin: vfox 0.3.2 or later, which `metadata.lua` names as its minimum, and the platform's packages from [platforms](platforms.md). `vfox link --detect` and the removal of a build on uninstall need vfox 1.1.0 or later.
