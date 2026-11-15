# 问题排查

[中文](troubleshooting.md) | [English](../troubleshooting.md)

下面的提示来自插件、`bin/install`，或者插件失败时的 vfox。每一条都说明了它的含义和对应的处理方法。

## `vfox requires hook support`

`vfox use -p` 会把 PHP 的选择写进项目，它需要先在 Shell 里激活 vfox。先激活，再运行命令：

```shell
eval "$(vfox activate bash)"          # bash 或 zsh
Invoke-Expression "$(vfox activate pwsh)"   # PowerShell
```

## `PHP version not found: <version>`

没有与你写的版本匹配的发布版本。请和 `vfox search php` 的列表对照。记住 `-nts` 只在 Windows 上存在，并且 NTS 写法需要完整的版本号，即 `8.4.5-nts`，而不是 `8.4-nts`。见[版本与命名](versions.md)。

## `No PHP releases found for windows/arm64`

PHP 没有为这个架构发布构建。在 Windows on ARM 上没有可以安装的版本。

## `Failed to fetch PHP releases from <address>: ...`

插件无法读取发布列表。地址就是它尝试访问的那个。用浏览器或 `curl` 打开它，确认能否访问。在代理后面时，请像配置其他下载一样配置 vfox 的代理。如果地址可以访问，再试一次：请求偶尔失败一次，第二次往往就成功了。

## Linux 和 macOS

### `PHP cannot be installed into a path with spaces`

安装路径含有空格，例如 `/home/John Doe/.vfox`。PHP 的 `make install` 无法安装到这样的路径，所以插件会在编译之前停止。请把 `VFOX_HOME` 设为不含空格的路径，例如 `/opt/vfox`，然后重新安装。见[平台](platforms.md#linux)。

## Linux

### `Compilation Failure.`

编译中途停止了，这条消息上方的输出会说明原因。常见原因是缺少某个开发包，比如 `libxml2-dev` 或 `libonig-dev`。软件包列表见[平台](platforms.md#linux)。

### `Installer corrupt`

Composer 的安装器与 Composer 公布的 sha384 不一致，所以 `bin/install` 删除了它并停止。请重新安装。如果每次都这样，说明你和 getcomposer.org 之间有东西（比如代理）在改动文件。

## macOS

### `ERROR: Please install homebrew for OSX`

构建用 Homebrew 提供库。请先安装它，再安装[平台](platforms.md#macos)中列出的 formula。

### `ERROR: PHP 8.0.30 requires openssl@1.1`

PHP 7.x 和 8.0 需要 OpenSSL 1.1，而 Homebrew 已不再通过常规的 formula 提供它。请安装兼容的 OpenSSL 1.1，或者设置 `PHP_CONFIGURE_OPTIONS` 并指向它。见[平台](platforms.md#openssl)。

### `gmp not found, not including in installation`

仅供参考。GMP 是可选的，没有它构建也会继续。用 Homebrew 安装 `gmp` 即可启用。

## Windows

### `The Composer installer does not match the sha384 that Composer publishes`

插件下载的安装器与 Composer 公布的不一致，所以安装在 Composer 装好之前就停止了。请重新安装。如果每次都失败，说明你和 getcomposer.org 之间有东西（比如改写 HTTPS 响应的代理）在改动文件。

### `The code execution cannot proceed because VCRUNTIME140.dll was not found`

PHP 的构建需要 Microsoft Visual C++ Redistributable，插件不会安装它。请从 Microsoft 安装后再运行 PHP。

### `Failed to install composer.`

插件无法用 `php.exe` 运行 Composer 的安装器。请先确认 PHP 能单独运行（`php -v`），以及 getcomposer.org 可以访问，然后重新安装。

## 其他

### 安装过程中出现了别的问题

用 `vfox --debug install php@<version>` 运行安装。vfox 会打印它向插件询问了什么，以及插件怎样回答。报告问题时请附上这些输出，见[问题追踪](https://github.com/version-fox/vfox-php/issues)。
