# Build options

[中文](zh-CN/configuration.md) | [English](configuration.md)

On Linux and macOS, `bin/install` compiles PHP when `vfox install` runs. It reads these environment variables from the shell that runs `vfox install`:

| Variable | Effect |
| --- | --- |
| `PHP_CONFIGURE_OPTIONS` | Replaces the platform options, the ones for the system libraries (OpenSSL, curl, readline and so on). The global options are still added after them. |
| `PHP_WITHOUT_PEAR` | Any value other than `no` builds without PEAR (`--without-pear`). Unset or `no` builds with PEAR (`--with-pear`). |
| `PHP_WITHOUT_PCRE_JIT` | Unset or `no` adds `--without-pcre-jit`. Any other value adds nothing, so PCRE JIT stays on. The meaning is the reverse of what the name suggests, so check the value you set. |
| `MAKEFLAGS` | Passed to `make`, which compiles PHP, for example `MAKEFLAGS=-j8`. |

```shell
MAKEFLAGS=-j8 PHP_WITHOUT_PEAR=yes vfox install php@8.4
```

On Windows these variables do nothing: the plugin unpacks a prebuilt build and compiles nothing.

## PHP_CONFIGURE_OPTIONS

When you set it, you own the library paths. The plugin does not choose the OpenSSL path on macOS, and it does not add the `--with-` options it would otherwise find for the system libraries. The global options, such as `--enable-mbstring`, are still added after your value:

```shell
PHP_CONFIGURE_OPTIONS="--with-openssl=/opt/openssl --with-curl" vfox install php@8.4
```

The `--with-openssl` above is the option that enables HTTPS. Without it, PHP is built without OpenSSL, and Composer cannot download packages.

## The options that always apply

`construct_configure_options` in `bin/install` lists the options added to every build: the `--enable-` extensions, the `--with-` options that do not depend on the system, and the configuration paths under the install directory. To see what a PHP was built with, run `php -i` and read the Configure Command line.
