# vfox-php

[中文](README_CN.md) | [English](README.md)

[PHP](https://www.php.net/) plugin for [vfox](https://vfox.dev/).

On Linux and macOS it compiles PHP from the source releases on php.net. On Windows it downloads the prebuilt builds from windows.php.net. Every install comes with Composer.

## Install

After installing [vfox](https://github.com/version-fox/vfox), add the plugin, install a PHP and select it:

```shell
vfox add php
vfox search php
vfox install php@latest
vfox use --global php@latest
php -v
```

`php -v` shows the PHP that is selected. For `php` to be on the `PATH`, vfox has to be hooked into your shell, see vfox's [quick start](https://vfox.dev/guides/quick-start.html).

## Versions

A version is a full release, a line such as `8.4`, or `latest`:

```shell
vfox install php@latest     # the newest release
vfox install php@8.4        # the newest 8.4.x
vfox install php@8.4.5      # exactly 8.4.5
vfox install php@8.4.5-nts  # Windows only: the NTS build of 8.4.5
```

On Windows a plain version is the thread-safe (TS) build, and `-nts` selects the non-thread-safe (NTS) build. See [docs/versions.md](docs/versions.md) for how a version is matched, where the lists come from and the errors you may see.

## Prerequisites

On Linux and macOS, PHP installation requires some dependencies: a compiler and the development libraries that PHP is built against. The packages for each system are listed in [docs/platforms.md](docs/platforms.md). Windows needs none.

## Platforms

- **Linux and macOS** compile the source release. Architectures that CI runs: Linux amd64 and arm64.
- **Windows** downloads x64 and x86 builds. PHP publishes no ARM64 build for Windows, so there is nothing to install on Windows on ARM.

## Documentation

**Using the plugin**

- [Versions and names](docs/versions.md): how a version is matched, the lists and the errors
- [Installs already on the machine](docs/link.md): `vfox link --detect php` adopts a PHP that is already installed
- [Platforms](docs/platforms.md): what each system builds or downloads, and what it needs
- [Build options](docs/configuration.md): the environment variables that change how PHP is built
- [Troubleshooting](docs/troubleshooting.md): the messages you may see and what to do about them
- [Changes](docs/changes.md): what each release changed

**Working on the plugin**

- [Install from source](docs/install-from-source.md): trying a checkout of this repository before a release
- [Development](docs/development.md): how the plugin works, the checks, and how to release it
- [E2E tests](docs/e2e.md): the container tests and the dev container
