# Platforms

[中文](zh-CN/platforms.md) | [English](platforms.md)

The plugin does one of two things, depending on the system: it compiles PHP from the source release, or it downloads a prebuilt build.

| System | Architectures | What vfox installs |
| --- | --- | --- |
| Linux | amd64 and arm64, both run in CI | the source release, compiled by `bin/install` |
| macOS | the same source build; CI's macOS job runs on `macos-latest` | the source release, compiled by `bin/install` |
| Windows | x64 (amd64) and x86 (386) | the prebuilt TS or NTS build from windows.php.net |
| Windows on ARM | none | nothing: PHP publishes no ARM64 build, and the plugin reports `No PHP releases found for windows/arm64` |

## Linux

`bin/install` compiles PHP. It needs a compiler and the development libraries below. This is the list the E2E image installs on Ubuntu 26.04:

```shell
sudo apt-get install --assume-yes autoconf bison build-essential ca-certificates curl gettext git \
    libcurl4-openssl-dev libedit-dev libgd-dev libicu-dev libjpeg-dev libonig-dev libpng-dev libpq-dev \
    libreadline-dev libsqlite3-dev libssl-dev libxml2-dev libxslt-dev libzip-dev openssl pkg-config \
    re2c zip zlib1g-dev libgmp-dev libsodium-dev
```

The install path must not contain a space. PHP's `make install` cannot install into such a path, so `bin/install` refuses it before the compile and names the path. Set `VFOX_HOME` to a path without spaces, such as `/opt/vfox`. A home directory with a space in its name, such as `/home/John Doe`, needs this too, because the default install path lies under it.

JPEG and PNG support come from the system libgd (`libgd-dev`), because the build uses `--with-external-gd`. The E2E suite checks that gd reports JPEG support.

gmp and sodium are optional. `bin/install` enables each one when its library and its header are installed, and checks both: the library with `ldconfig`, the header with the compiler. Without them, the build prints `gmp not found, not including in installation` (or the sodium line) and carries on. The `libgmp-dev` and `libsodium-dev` packages in the list above provide them.

## macOS

As on Linux, the install path must not contain a space: `bin/install` refuses it before the compile. The build uses Homebrew. Without it, the build stops with `ERROR: Please install homebrew for OSX`. Install these formulae:

```shell
brew install autoconf automake bison freetype gd gettext icu4c krb5 libedit libiconv libjpeg libpng libxml2 libxslt libzip openssl@3 pkg-config re2c zlib
```

Two optional formulae add extensions when they are installed: `brew install gmp libsodium`. `bin/install` passes `--with-gmp` and `--with-sodium` for them. When one is missing, the build prints `gmp not found, not including in installation` (or the sodium line) and carries on. ImageMagick does not add an extension: `bin/install` has no option for it.

### OpenSSL

PHP 8.1 and newer build against `openssl@3`. PHP 7.x and 8.0 need OpenSSL 1.1, which Homebrew no longer supplies through its normal formulae. For those versions the build stops with `ERROR: PHP 8.0.30 requires openssl@1.1; install a compatible dependency before building.` Install a compatible OpenSSL 1.1, or see the [PHP OpenSSL requirements](https://www.php.net/manual/en/openssl.requirements.php). With the default options, an old PHP never picks OpenSSL 3 silently, and the build never leaves OpenSSL out.

If you set `PHP_CONFIGURE_OPTIONS`, the plugin does not choose the OpenSSL path for you. See [build options](configuration.md).

## Windows

Windows needs no compiler. The plugin unpacks the build from windows.php.net and then:

- writes `php.ini` next to `php.exe`, from `php.ini-development`. It sets `extension_dir` to the absolute `ext` folder and enables `openssl`, so Composer can fetch packages over HTTPS;
- downloads Composer's installer from getcomposer.org and checks it against the sha384 that Composer publishes. If they differ, the install stops and Composer is not installed. The check is made by PHP, which is already in place at that point;
- runs the installer with `php.exe`, and writes a `composer.bat` next to it.

Install paths may hold spaces, as a Windows user profile often does. The plugin quotes them: CI installs into `C:\vfox home`.

The builds load the Microsoft Visual C++ Redistributable, which the plugin does not install. If `php.exe` reports a missing `VCRUNTIME140.dll`, install the redistributable from Microsoft.

## Composer

Every install gets Composer: `composer` on Linux and macOS, and `composer.bat` on Windows. The plugin installs it as part of the install, so `composer -V` works once PHP is selected.
