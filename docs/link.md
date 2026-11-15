# Using PHP installs that are already on the machine

[中文](zh-CN/link.md) | [English](link.md)

If PHP is already on the machine, `vfox link --detect php` adopts it instead of compiling another copy. It may come from Homebrew, a build made by hand under `/opt` or `/usr/local`, a version manager, Scoop, XAMPP or another Windows stack, or the PATH. It needs vfox 1.1.0 or later (`vfox --version`).

```bash
vfox link --detect php
```

vfox lists what the plugin found and links what you pick. `vfox link --detect -y php` links everything without asking. Afterwards `vfox use php@...` works as usual: `vfox list php` marks linked versions `(linked → <path>)`, and `vfox uninstall` removes only the link, leaving the PHP where it is.

## What it finds

- Homebrew kegs: `php` and `php@X.Y` under `/opt/homebrew/opt`, `/usr/local/opt` and Linuxbrew
- Folders whose names start with `php` under `/opt` and `/usr/local`, such as `/opt/php-8.4`
- The version managers asdf, mise and phpenv
- MAMP on macOS (`/Applications/MAMP/bin/php`)
- On Windows: Scoop (`%USERPROFILE%\scoop\apps\php`), XAMPP (`C:\xampp\php`), Laragon, WampServer, Chocolatey, folders named `php` under `C:\`, `C:\tools` and `C:\Program Files`, and `C:\php`
- The CI runner tool caches (`/opt/hostedtoolcache/PHP` and `C:\hostedtoolcache\windows\PHP`)
- The PHP that the PATH names, when it is in a folder of its own

## What it skips

- A PHP whose folder is a shared system directory, such as `/usr`, `/usr/local`, `/opt`, `C:\` or the Scoop folder itself. Linking one would link the whole system, so a PHP that a distribution installs under `/usr/bin` is not offered. Link it by hand, as described below.
- The Scoop shims, which only forward to an install.
- Installs that vfox manages: anything under `VFOX_HOME`, the plugin's own build folders, and anything under a `.vfox` folder.
- A PHP that does not answer `php -v`.

## Version names

A found PHP is named the way `vfox install` names it. Its version comes from `php -v`, then `-nts` is added for an NTS build on Windows, since the plugin installs TS builds there without a suffix, and `-zts` for a ZTS build elsewhere, since the plugin installs NTS builds without one. An install that is found twice under one version is offered once, with the first path.

## Linking by hand

Where `--detect` does not look, point at the install yourself. It is the folder that holds `bin` (on Windows, the folder that holds `php.exe`):

```bash
vfox link php@8.4.5 /opt/php-8.4.5
vfox use php@8.4.5
```

## Limits

- A linked PHP is used as it is. The plugin installs Composer into the PHP it builds; a linked PHP has the Composer it came with, if any.
- `vfox uninstall` removes the link only. The PHP stays where it is.
