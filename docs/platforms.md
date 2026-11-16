# Platforms

[中文](zh-CN/platforms.md) | [English](platforms.md)

The plugin does one of two things, depending on the system: it compiles PHP from the source release, or it downloads a prebuilt build.

| System | Architectures | What vfox installs |
| --- | --- | --- |
| Linux | amd64 and arm64, both run in CI | the source release, compiled by the plugin |
| macOS | the same source build; CI's macOS job runs on `macos-latest` | the source release, compiled by the plugin |
| Windows | x64 (amd64) and x86 (386) | the prebuilt TS or NTS build from windows.php.net |
| Windows on ARM | none | nothing: PHP publishes no ARM64 build, and the plugin reports `No PHP releases found for windows/arm64` |

## Linux

The plugin compiles PHP. It needs a compiler and the development libraries below. This is the list the E2E image installs on Ubuntu 26.04:

```shell
sudo apt-get install --assume-yes autoconf bison build-essential ca-certificates curl gettext git \
    libcurl4-openssl-dev libedit-dev libgd-dev libicu-dev libjpeg-dev libonig-dev libpng-dev libpq-dev \
    libreadline-dev libsqlite3-dev libssl-dev libxml2-dev libxslt-dev libzip-dev openssl pkg-config \
    re2c zip zlib1g-dev libgmp-dev libsodium-dev
```

Before it compiles anything, the plugin checks the build dependencies on the system: the compiler, `make`, `autoconf`, `pkg-config` and `curl`, and the libraries that the configure options use. A missing one stops the install at once. The message lists each missing item with the Debian or Ubuntu package that provides it:

```text
ERROR: PHP cannot be built, because these build dependencies are missing. Nothing was compiled:
  - libzip: --with-zip
Install them and run vfox install again. The packages are named for Debian and Ubuntu:
  sudo apt-get install --assume-yes libzip-dev
```

`bison` and `re2c` are not checked. The release tarball ships the generated parser and scanner, so only a git checkout needs them. The platform requirements, for OpenSSL, readline, gettext and xsl, are checked only when `PHP_CONFIGURE_OPTIONS` is not set, because the platform options are used only then.

An install path may hold a space, such as a `VFOX_HOME` under `/home/John Doe`. PHP's `make install` and the `pear` and `pecl` scripts do not quote their paths, so PHP cannot be built or installed under such a path. The plugin therefore builds PHP in a directory without spaces, and the install path becomes a link to it. The build directory is `builds/<checksum>` under the first of these that is set and has no space: `$XDG_DATA_HOME/vfox-php`, then `~/.local/share/vfox-php`, then `/var/tmp/vfox-php-<uid>`. The checksum comes from the install path, so two `VFOX_HOME`s never share one. `vfox uninstall` removes the link, and the build directory with it. That needs vfox 0.4.0 or later, which passes the install path to the `PreUninstall` hook. Older vfox has no such hook, so remove the build directory by hand.

JPEG and PNG support come from the system libgd (`libgd-dev`), because the build uses `--with-external-gd`. The E2E suite checks that gd reports JPEG support.

gmp and sodium are optional. The plugin enables each one when its library and its header are installed, and checks both: the library with `ldconfig`, the header with the compiler. Without them, the build prints `gmp not found, not including in installation` (or the sodium line) and carries on. The `libgmp-dev` and `libsodium-dev` packages in the list above provide them.

## macOS

As on Linux, an install path with a space is built in a directory without spaces; see [Linux](#linux). The build uses Homebrew. Without it, the build stops with `ERROR: Please install homebrew for OSX`. Install these formulae:

```shell
brew install autoconf automake bison freetype gd gettext icu4c krb5 libedit libiconv libjpeg libpng libxml2 libxslt libzip openssl@3 pkg-config re2c zlib
```

Two optional formulae add extensions when they are installed: `brew install gmp libsodium`. The plugin passes `--with-gmp` and `--with-sodium` for them. When one is missing, the build prints `gmp not found, not including in installation` (or the sodium line) and carries on. ImageMagick does not add an extension: the plugin has no option for it.

### OpenSSL

PHP 8.1 and newer build against `openssl@3`. PHP 7.x and 8.0 need OpenSSL 1.1, which Homebrew no longer supplies through its normal formulae. For those versions the build stops with `ERROR: PHP 8.0.30 requires openssl@1.1; install a compatible dependency before building.` Install a compatible OpenSSL 1.1, or see the [PHP OpenSSL requirements](https://www.php.net/manual/en/openssl.requirements.php). With the default options, an old PHP never picks OpenSSL 3 silently, and the build never leaves OpenSSL out.

If you set `PHP_CONFIGURE_OPTIONS`, the plugin does not choose the OpenSSL path for you. See [build options](configuration.md).

## Windows

Windows needs no compiler. The builds load the Microsoft Visual C++ 2015-2022 Redistributable, and the install adds it when it is missing. The plugin unpacks the build from windows.php.net and then:

- installs the Redistributable when the registry does not record it. The plugin downloads the x64 build from [Microsoft](https://aka.ms/vs/17/release/vc_redist.x64.exe), or the x86 build (`vc_redist.x86.exe`) for x86 PHP, checks that Microsoft signed it, and runs it silently. The installer needs administrator rights, so Windows asks for permission first. If the download or the install fails, the install stops and names the link to install the build yourself;
- runs `php.exe` once. If it does not start, the install stops there and says how to repair the Redistributable, before it writes `php.ini` or downloads Composer;
- writes `php.ini` next to `php.exe`, from `php.ini-development`. It sets `extension_dir` to the absolute `ext` folder and enables `openssl`, so Composer can fetch packages over HTTPS;
- downloads Composer's installer from getcomposer.org and checks it against the sha384 that Composer publishes. If they differ, the install stops and Composer is not installed. The check is made by PHP, which is already in place at that point;
- runs the installer with `php.exe`, and writes a `composer.bat` next to it.

Install paths may hold spaces, as a Windows user profile often does. The plugin quotes them: CI installs into `C:\vfox home`.

If you start `php.exe` yourself and Windows reports that `VCRUNTIME140.dll` was not found, the Redistributable is missing for that PHP. Install the build named above, then run `php.exe` again.

## Composer

Every install gets Composer: `composer` on Linux and macOS, and `composer.bat` on Windows. The plugin installs it as part of the install, so `composer -V` works once PHP is selected.
