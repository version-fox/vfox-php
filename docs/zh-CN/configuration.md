# 构建选项

[中文](configuration.md) | [English](../configuration.md)

在 Linux 和 macOS 上，`vfox install` 运行时由插件编译 PHP。它读取运行 `vfox install` 的那个 Shell 里的以下环境变量：

| 变量 | 作用 |
| --- | --- |
| `PHP_CONFIGURE_OPTIONS` | 替换平台选项，即针对系统库（OpenSSL、curl、readline 等）的那些选项。全局选项仍会追加在它们后面。 |
| `PHP_WITHOUT_PEAR` | 仅对 PHP 5.3 到 7.3 有效。设为除 `no` 以外的任何值，构建时不带 PEAR（`--without-pear`）。未设置或设为 `no`，则带 PEAR（`--with-pear`）。 |
| `PHP_WITH_PEAR` | 仅对 PHP 7.4 及以后的版本有效。设为除 `no` 以外的任何值，构建时带 PEAR（`--with-pear`），从而安装 `pear` 和 `pecl`。PHP 7.4 已弃用 `--with-pear`，因此 configure 会对此发出警告。未设置或设为 `no`，则不带 PEAR。 |
| `PHP_WITH_MHASH` | 仅对 PHP 8.4 及以后的版本有效。设为除 `no` 以外的任何值，构建时带 mhash 函数（`--with-mhash`）。PHP 8.4 已弃用 `--with-mhash`，因此 configure 会对此发出警告。未设置或设为 `no`，则不带这些函数；`hash_*` 函数无论如何都在。PHP 8.4 之前的版本始终构建 mhash 函数，因此该变量对它们无效。 |
| `PHP_WITHOUT_PCRE_JIT` | 设为除 `no` 以外的任何值，构建时不带 PCRE JIT（`--without-pcre-jit`）。PHP 5.x 没有这个选项，所以该变量在它上面不起作用。未设置或设为 `no`，保持 PHP 的默认值，即开启 PCRE JIT。 |
| `MAKEFLAGS` | 传给编译 PHP 的 `make`，例如 `MAKEFLAGS=-j8`。 |

```shell
MAKEFLAGS=-j8 PHP_WITH_PEAR=yes vfox install php@8.5
```

在 Windows 上这些变量不起作用：插件解压的是预编译构建，不做编译。

未设置 `PHP_WITHOUT_PCRE_JIT` 时，PCRE JIT 保持开启，与 PHP 的默认值一致。

在 Linux 和 macOS 上，无论这些变量如何设置，含空格的安装路径都会在不含空格的目录里构建，见[平台](platforms.md#linux)。

## PHP_CONFIGURE_OPTIONS

设置它之后，库路径就由你自己负责。插件不再在 macOS 上选择 OpenSSL 的路径，也不再为系统库添加它原本会找到并加上的 `--with-` 选项。全局选项（如 `--enable-mbstring`）仍然会追加在你的值后面：

```shell
PHP_CONFIGURE_OPTIONS="--with-openssl=/opt/openssl --with-curl" vfox install php@8.4
```

上面的 `--with-openssl` 是启用 HTTPS 的选项。没有它，PHP 会在没有 OpenSSL 的情况下编译，Composer 也就无法下载包。

## 始终生效的选项

`lib/php_build.lua` 里的 `global_options` 和 `version_options` 列出了每次构建都会加上的选项：`--enable-` 开头的扩展、与系统无关的 `--with-` 选项，以及安装目录下的配置路径。想知道某个 PHP 是怎么编译出来的，运行 `php -i`，看 Configure Command 那一行。
