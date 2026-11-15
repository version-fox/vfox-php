# Changes

[中文](zh-CN/changes.md) | [English](changes.md)

What each release changed. The releases before 0.3.0 are on the [GitHub releases page](https://github.com/version-fox/vfox-php/releases).

## Unreleased

- Development: a dev container, Go E2E suites for Linux and Windows that install PHP with vfox inside containers, lint, format and license-header checks in CI, and documentation in English and Chinese.
- Linux: `bin/install` checks the build dependencies before it compiles: the compiler, `make`, `autoconf`, `pkg-config` and `curl`, and the libraries that the configure options use. A missing one stops the install at once, and the message names each missing item and its Debian or Ubuntu package. Before, the install failed in configure or make, after a long build. See [platforms](platforms.md#linux).
- The Lua and shell sources carry the Apache-2.0 license header.
- Linux and macOS: PCRE JIT is on by default, as in PHP. `PHP_WITHOUT_PCRE_JIT` turns it off. The variable was tested the wrong way round, so builds had JIT off by default.
- Linux: gmp and sodium are found through the system library cache and their headers, without `locate`. JPEG and PNG come from the system libgd, as the build uses `--with-external-gd`, so the old `--with-jpeg-dir` and `--with-png-dir` options are gone.
- Linux and macOS: the Composer installer is fetched into PHP's `bin` directory, not into the directory the install was started from.
- Linux and macOS: an install path with a space works. PHP is built and installed in a directory without spaces (see [platforms](platforms.md#linux)), and the install path links to it. Before, PHP could not be built into such a path. `vfox uninstall` removes the build directory, through a new `PreUninstall` hook. Configure arguments are passed one by one.
- Windows: install paths with spaces work. The Composer steps quote their paths.
- Windows: the Composer installer is checked against the sha384 that Composer publishes before it runs, as on Linux and macOS.
- Windows: the install runs `php.exe` before it checks Composer's installer. Without the Visual C++ runtime, `php.exe` does not start, and the install used to report a sha384 mismatch. It now stops and names the Redistributable to install. See [troubleshooting](troubleshooting.md#windows).
- Windows: NTS builds whose name carries a rebuild number, such as `8.5.12-1-nts`, are listed and can be installed.
- All platforms: `vfox link --detect php` finds the PHP installs that are already on the machine and links the ones you pick, with a `Detect` hook. It needs vfox 1.1.0 or later. See [installs already on the machine](link.md).
- Linux and macOS: `vfox install php@<version>-zts` builds the thread-safe (ZTS) PHP of a release from its source. A plain version is still the NTS build. PHP 8.0 and later are configured with `--enable-zts`, PHP 5.x and 7.x with `--enable-maintainer-zts`.
- Linux, macOS and Windows: `vfox use` of a line or a major takes the default build of its release, the plain name, as `vfox install` does, and never a `-zts` or `-nts` build. A `-zts` or `-nts` build is selected by naming it.

## 0.3.2

- Optional dependency diagnostics, such as `gmp not found`, are printed to stderr and no longer end up in the configure arguments.

## 0.3.1

- Restored PHP release discovery and platform installation.
- Releases are published by the shared plugin workflow.
- CI initialises vfox before it selects PHP, and it verifies the managed PHP.
- CI no longer keeps an empty legacy config file.

## 0.3.0

- Linux supports the LTS releases.
- Downloads use the redirected URLs.
- Without Homebrew, Linux builds include gmp and sodium when they are found.
- The README was updated.
