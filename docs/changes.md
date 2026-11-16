# Changes

[中文](zh-CN/changes.md) | [English](changes.md)

What each release changed. Dates are in UTC: the day each release was published on GitHub. The releases before 0.3.0 are on the [GitHub releases page](https://github.com/version-fox/vfox-php/releases).

## Unreleased

- Linux and macOS: the plugin passes only the configure options that the PHP version being built takes, from PHP 5.3 to 8.5. It used to pass every option to every version. configure ignores an option it does not know, but warns about it, so PHP 8 builds printed warnings for options that PHP 8 no longer has, such as `--enable-wddx`, `--with-xmlrpc` and `--with-mysql`. The extensions that a build gets do not change. `--with-pear` and `--with-mhash` are still passed: PHP warns that they are deprecated, but they install PEAR and the mhash functions, as the plugin always has.
- Linux and macOS: the build of PHP is written in Lua (`lib/php_build.lua`), and the shell script `bin/install` is removed. The options, the dependency checks, the build and Composer work as before. The Go tests of `bin/install` are replaced by Lua tests: `tests/php_build_test.lua` runs on a fake machine, and `tests/php_build_brew_test.lua` checks the options against Homebrew on macOS.

## 0.3.3 (2026-11-15)

- Development: a dev container, Go E2E suites for Linux and Windows that install PHP with vfox inside containers, lint, format and license-header checks in CI, and documentation in English and Chinese.
- Linux: the plugin checks the build dependencies before it compiles: the compiler, `make`, `autoconf`, `pkg-config` and `curl`, and the libraries that the configure options use. A missing one stops the install at once, and the message names each missing item and its Debian or Ubuntu package. Before, the install failed in configure or make, after a long build. See [platforms](platforms.md#linux).
- The Lua and shell sources carry the Apache-2.0 license header.
- Linux and macOS: PCRE JIT is on by default, as in PHP. `PHP_WITHOUT_PCRE_JIT` turns it off. The variable was tested the wrong way round, so builds had JIT off by default.
- Linux: gmp and sodium are found through the system library cache and their headers, without `locate`. JPEG and PNG come from the system libgd, as the build uses `--with-external-gd`, so the old `--with-jpeg-dir` and `--with-png-dir` options are gone.
- Linux and macOS: the Composer installer is fetched into PHP's `bin` directory, not into the directory the install was started from.
- Linux and macOS: an install path with a space works. PHP is built and installed in a directory without spaces (see [platforms](platforms.md#linux)), and the install path links to it. Before, PHP could not be built into such a path. `vfox uninstall` removes the build directory, through a new `PreUninstall` hook. Configure arguments are passed one by one.
- Windows: install paths with spaces work. The Composer steps quote their paths.
- Windows: the Composer installer is checked against the sha384 that Composer publishes before it runs, as on Linux and macOS.
- Windows: without the Visual C++ runtime, `php.exe` does not start, and the install used to report a sha384 mismatch. Now the install adds the Microsoft Visual C++ 2015-2022 Redistributable when the registry does not record it: it downloads the build from Microsoft, checks that Microsoft signed it, and runs it silently, after Windows asks for permission. Then it runs `php.exe`, and stops if that still does not start. See [platforms](platforms.md#windows).
- Windows: NTS builds whose name carries a rebuild number, such as `8.5.12-1-nts`, are listed and can be installed.
- All platforms: `vfox link --detect php` finds the PHP installs that are already on the machine and links the ones you pick, with a `Detect` hook. It needs vfox 1.1.0 or later. See [installs already on the machine](link.md).
- Linux and macOS: `vfox install php@<version>-zts` builds the thread-safe (ZTS) PHP of a release from its source. A plain version is still the NTS build. PHP 8.0 and later are configured with `--enable-zts`, PHP 5.x and 7.x with `--enable-maintainer-zts`.
- Linux, macOS and Windows: `vfox use` of a line or a major takes the default build of its release, the plain name, as `vfox install` does, and never a `-zts` or `-nts` build. A `-zts` or `-nts` build is selected by naming it.

## 0.3.2 (2026-09-12)

- Optional dependency diagnostics, such as `gmp not found`, are printed to stderr and no longer end up in the configure arguments.

## 0.3.1 (2026-09-12)

- Restored PHP release discovery and platform installation.
- Releases are published by the shared plugin workflow.
- CI initialises vfox before it selects PHP, and it verifies the managed PHP.
- CI no longer keeps an empty legacy config file.

## 0.3.0 (2025-09-29)

- Linux supports the LTS releases.
- Downloads use the redirected URLs.
- Without Homebrew, Linux builds include gmp and sodium when they are found.
- The README was updated.
