# Build options

[中文](zh-CN/configuration.md) | [English](configuration.md)

On Linux and macOS, the plugin compiles PHP when `vfox install` runs. It reads these environment variables from the shell that runs `vfox install`:

| Variable | Effect |
| --- | --- |
| `PHP_CONFIGURE_OPTIONS` | Replaces the platform options, the ones for the system libraries (OpenSSL, curl, readline and so on). The global options are still added after them. |
| `PHP_WITHOUT_PEAR` | PHP 5.3 to 7.3 only. Any value other than `no` builds without PEAR (`--without-pear`). Unset or `no` builds with PEAR (`--with-pear`). |
| `PHP_WITH_PEAR` | PHP 7.4 and later only. Any value other than `no` builds with PEAR (`--with-pear`), which installs `pear` and `pecl`. PHP 7.4 deprecates `--with-pear`, so configure prints a warning for it. Unset or `no` builds without PEAR. |
| `PHP_WITHOUT_PCRE_JIT` | Any value other than `no` builds without PCRE JIT (`--without-pcre-jit`). PHP 5.x has no such option, so the variable has no effect there. Unset or `no` keeps PHP's default, PCRE JIT on. |
| `MAKEFLAGS` | Passed to `make`, which compiles PHP, for example `MAKEFLAGS=-j8`. |

```shell
MAKEFLAGS=-j8 PHP_WITH_PEAR=yes vfox install php@8.5
```

On Windows these variables do nothing: the plugin unpacks a prebuilt build and compiles nothing.

With `PHP_WITHOUT_PCRE_JIT` unset, PCRE JIT is on, as PHP has it by default.

On Linux and macOS an install path with a space is built in a directory without spaces, whatever these variables are set to. See [platforms](platforms.md#linux).

## PHP_CONFIGURE_OPTIONS

When you set it, you own the library paths. The plugin does not choose the OpenSSL path on macOS, and it does not add the `--with-` options it would otherwise find for the system libraries. The global options, such as `--enable-mbstring`, are still added after your value:

```shell
PHP_CONFIGURE_OPTIONS="--with-openssl=/opt/openssl --with-curl" vfox install php@8.4
```

The `--with-openssl` above is the option that enables HTTPS. Without it, PHP is built without OpenSSL, and Composer cannot download packages.

## The options that always apply

`global_options` and `version_options` in `lib/php_build.lua` list the options added to every build: the `--enable-` extensions, the `--with-` options that do not depend on the system, and the configuration paths under the install directory. To see what a PHP was built with, run `php -i` and read the Configure Command line.
