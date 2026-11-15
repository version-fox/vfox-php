# 平台

[中文](platforms.md) | [English](../platforms.md)

插件根据系统的不同，做两件事之一：从源码发布包编译 PHP，或者下载预编译的构建。

| 系统 | 架构 | vfox 安装的内容 |
| --- | --- | --- |
| Linux | amd64 和 arm64，CI 两者都运行 | 源码发布包，由 `bin/install` 编译 |
| macOS | 同一份源码构建；CI 的 macOS 任务运行在 `macos-latest` 上 | 源码发布包，由 `bin/install` 编译 |
| Windows | x64（amd64）和 x86（386） | windows.php.net 上预编译的 TS 或 NTS 构建 |
| Windows on ARM | 无 | 什么都不装：PHP 没有发布 ARM64 构建，插件会报 `No PHP releases found for windows/arm64` |

## Linux

`bin/install` 编译 PHP，需要一个编译器和下面这些开发库。这是 E2E 镜像在 Ubuntu 26.04 上安装的列表：

```shell
sudo apt-get install --assume-yes autoconf bison build-essential ca-certificates curl gettext git \
    libcurl4-openssl-dev libedit-dev libgd-dev libicu-dev libjpeg-dev libonig-dev libpng-dev libpq-dev \
    libreadline-dev libsqlite3-dev libssl-dev libxml2-dev libxslt-dev libzip-dev openssl pkg-config \
    re2c zip zlib1g-dev libgmp-dev libsodium-dev
```

安装路径可以含有空格，例如 `/home/John Doe` 下的 `VFOX_HOME`。PHP 的 `make install` 以及 `pear`、`pecl` 脚本都不会给路径加引号，所以 PHP 无法直接构建或安装到这样的路径。因此 `bin/install` 会在不含空格的目录里构建 PHP，安装路径则链接到该目录。构建目录依次取以下第一个可用的：已设置且不含空格的 `$XDG_DATA_HOME/vfox-php`；不含空格的主目录下的 `~/.local/share/vfox-php`；若主目录也含空格，则为 `/var/tmp/vfox-php-<uid>`。`vfox uninstall` 会删除链接，连同构建目录一起删除。这需要 vfox 把安装路径传给 `PreUninstall` 钩子，vfox 1.1.0 会传。若 vfox 不传，请手动删除构建目录。

JPEG 和 PNG 的支持来自系统的 libgd（`libgd-dev`），因为构建使用 `--with-external-gd`。E2E 套件会检查 gd 是否报告 JPEG 支持。

gmp 和 sodium 是可选的。`bin/install` 在对应的库和头文件都已安装时启用它：用 `ldconfig` 检查库，用编译器检查头文件，两者都要满足。缺少时，构建会打印 `gmp not found, not including in installation`（或 sodium 的那一行）并继续。上面列表中的 `libgmp-dev` 和 `libsodium-dev` 提供了这两者。

## macOS

与 Linux 一样，含空格的安装路径会在不含空格的目录里构建，见 [Linux](#linux)。构建依赖 Homebrew。没有它，构建会以 `ERROR: Please install homebrew for OSX` 停止。请安装下面这些 formula：

```shell
brew install autoconf automake bison freetype gd gettext icu4c krb5 libedit libiconv libjpeg libpng libxml2 libxslt libzip openssl@3 pkg-config re2c zlib
```

另外两个可选的 formula 会在安装后启用对应的扩展：`brew install gmp libsodium`。`bin/install` 找到它们时会传入 `--with-gmp` 和 `--with-sodium`。缺少时，构建会打印 `gmp not found, not including in installation`（或 sodium 的那一行）并继续。ImageMagick 不会启用任何扩展：`bin/install` 没有为它设置选项。

### OpenSSL

PHP 8.1 及更新的版本使用 `openssl@3` 编译。PHP 7.x 和 8.0 需要 OpenSSL 1.1，而 Homebrew 已不再通过常规的 formula 提供它。对这些版本，构建会以 `ERROR: PHP 8.0.30 requires openssl@1.1; install a compatible dependency before building.` 停止。请安装兼容的 OpenSSL 1.1，或参阅 [PHP 的 OpenSSL 要求](https://www.php.net/manual/en/openssl.requirements.php)。使用默认选项时，旧版本的 PHP 绝不会悄悄地选用 OpenSSL 3，构建也绝不会漏掉 OpenSSL。

如果你设置了 `PHP_CONFIGURE_OPTIONS`，插件就不再替你选择 OpenSSL 的路径。见[构建选项](configuration.md)。

## Windows

Windows 不需要编译器，但这些构建需要 Microsoft Visual C++ 2015-2022 Redistributable，插件不会安装它。请在安装 PHP 之前先从 [Microsoft](https://aka.ms/vs/17/release/vc_redist.x64.exe) 安装 x64 版（x86 版 PHP 则安装 `vc_redist.x86.exe`）。插件从 windows.php.net 解压构建，然后：

- 运行一次 `php.exe`。如果它无法启动，安装在此停止，并指出需要安装的 Redistributable，在此之前不会写入任何内容，也不会下载 Composer；
- 在 `php.exe` 旁边写入 `php.ini`，内容来自 `php.ini-development`。它把 `extension_dir` 设为绝对路径的 `ext` 目录，并启用 `openssl`，让 Composer 能通过 HTTPS 下载包；
- 从 getcomposer.org 下载 Composer 的安装器，并与 Composer 公布的 sha384 核对。两者不一致时，安装停止，Composer 不会被安装。核对由 PHP 完成，此时 PHP 已经就位；
- 用 `php.exe` 运行安装器，并在旁边写入 `composer.bat`。

安装路径可能含有空格，Windows 的用户目录常常如此。插件会给路径加引号；CI 就安装到 `C:\vfox home`。

如果你自己启动 `php.exe` 时 Windows 提示找不到 `VCRUNTIME140.dll`，说明缺少这个运行库，请按上面的方法安装。

## Composer

每次安装都会附带 Composer：Linux 和 macOS 上是 `composer`，Windows 上是 `composer.bat`。插件在安装过程中把它装好，所以选中 PHP 之后 `composer -V` 就能运行。
