# Build options

[中文](zh-CN/configuration.md) | [English](configuration.md)

On Linux and macOS, `bin/install` compiles PHP when `vfox install` runs. It reads these environment variables from the shell that runs `vfox install`:

| Variable | Effect |
| --- | --- |
| `PHP_CONFIGURE_OPTIONS` | Replaces the platform options, the ones for the system libraries (OpenSSL, curl, readline and so on). The global options are still added after them. |
| `PHP_WITHOUT_PEAR` | Any value other than `no` builds without PEAR (`--without-pear`). Unset or `no` builds with PEAR (`--with-pear`). |
| `PHP_WITHOUT_PCRE_JIT` | Any value other than `no` builds without PCRE JIT (`--without-pcre-jit`). Unset or `no` keeps PHP's default, PCRE JIT on. |
| `MAKEFLAGS` | Passed to `make`, which compiles PHP, for example `MAKEFLAGS=-j8`. |

```shell
MAKEFLAGS=-j8 PHP_WITHOUT_PEAR=yes vfox install php@8.4
```

On Windows these variables do nothing: the plugin unpacks a prebuilt build and compiles nothing.

Before this change, a Linux or macOS build with `PHP_WITHOUT_PCRE_JIT` unset was built without JIT, because the variable was tested the wrong way round. Builds now keep JIT on, as PHP does. Set `PHP_WITHOUT_PCRE_JIT=yes` to get the old result.

## PHP_CONFIGURE_OPTIONS

When you set it, you own the library paths. The plugin does not choose the OpenSSL path on macOS, and it does not add the `--with-` options it would otherwise find for the system libraries. The global options, such as `--enable-mbstring`, are still added after your value:

```shell
PHP_CONFIGURE_OPTIONS="--with-openssl=/opt/openssl --with-curl" vfox install php@8.4
```

The `--with-openssl` above is the option that enables HTTPS. Without it, PHP is built without OpenSSL, and Composer cannot download packages.

## The options that always apply

`construct_configure_options` in `bin/install` lists the options added to every build: the `--enable-` extensions, the `--with-` options that do not depend on the system, and the configuration paths under the install directory. To see what a PHP was built with, run `php -i` and read the Configure Command line.
