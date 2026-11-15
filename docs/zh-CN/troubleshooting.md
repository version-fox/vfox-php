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

没有与你写的版本匹配的发布版本。请和 `vfox search php` 的列表对照。记住 `-nts` 只在 Windows 上存在，`-zts` 只在 Linux 和 macOS 上存在，并且两种后缀都需要完整的版本号，例如 `8.4.5-zts`，而不是 `8.4-zts`。见[版本与命名](versions.md)。

## `No PHP releases found for windows/arm64`

PHP 没有为这个架构发布构建。在 Windows on ARM 上没有可以安装的版本。

## `Failed to fetch PHP releases from <address>: ...`

插件无法读取发布列表。地址就是它尝试访问的那个。用浏览器或 `curl` 打开它，确认能否访问。在代理后面时，请像配置其他下载一样配置 vfox 的代理。如果地址可以访问，再试一次：请求偶尔失败一次，第二次往往就成功了。

## Linux 和 macOS

### `Failed to remove the PHP build behind <path>`

`vfox uninstall` 无法删除安装路径所链接的构建目录。构建目录位于 `~/.local/share/vfox-php/builds`；主目录含空格时，位于 `/var/tmp` 之下。请检查该目录的权限，手动删除它，然后重新卸载。见[平台](platforms.md#linux)。

### `links to <target>, which is not a vfox-php build directory`

安装路径是一个链接，但它指向的目录不是插件创建的，所以 `vfox uninstall` 不会删除该目录，并且会停止。请用 `ls -l` 检查这个链接，如果不需要它，就手动删除该链接。

## Linux

### `ERROR: PHP cannot be built, because these build dependencies are missing`

`bin/install` 发现构建需要的一些工具或库在系统上缺失。它在移动源码或编译之前就停止了。消息下方的各行列出每个缺失的项目，`sudo apt-get install` 那一行给出提供它们的 Debian 或 Ubuntu 软件包。安装这些软件包后，重新运行 `vfox install`。在其他系统上，请安装对应的软件包。完整列表见[平台](platforms.md#linux)。

### `Compilation Failure.`

编译中途停止了，这条消息上方的输出会说明原因。现在构建开始前就会检查缺失的软件包，所以缺包时通常会在上面那条消息处停止。

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

### `The Visual C++ Redistributable is not installed, and it could not be downloaded`

注册表中没有记录该运行库时，插件会从 aka.ms 下载 Microsoft Visual C++ 2015-2022 Redistributable。下载失败，所以安装在写入任何内容之前就停止了。请检查网络和代理，然后重新安装。若想自己安装，请从 [Microsoft](https://aka.ms/vs/17/release/vc_redist.x64.exe) 安装 x64 版（x86 版 PHP 则安装 `vc_redist.x86.exe`），然后重新安装 PHP。错误信息中会给出适用于你的 PHP 的构建。

### `Windows did not start the Visual C++ Redistributable installer`

安装程序需要管理员权限，所以 Windows 会询问是否允许。如果你拒绝了提示，或 Windows 不允许提升权限，请重新安装并允许提示。你也可以按上面的方法自己安装该构建。

### `The Visual C++ Redistributable installer exited with code`

安装程序运行后失败，并返回了该退出码。请按错误信息中的链接自己安装该构建，然后重新安装 PHP。

### `is not signed by Microsoft, so it was not run`

下载的文件没有 Microsoft 的签名，所以插件没有运行它。改写 HTTPS 响应的代理或安全软件可能导致这种情况。请按错误信息中的链接自己安装该构建；如果这条消息再次出现，请检查代理。

### `php.exe does not start`

注册表已记录该运行库（或刚刚安装了它），但 `php.exe` 仍无法启动。请重启 Windows，然后重新安装 PHP。如果仍然失败，请在“应用和功能”中修复 Redistributable（x64 或 x86 项），然后重新安装 PHP。

### `The Composer installer does not match the sha384 that Composer publishes`

插件下载的安装器与 Composer 公布的不一致，所以安装在 Composer 装好之前就停止了。请重新安装。如果每次都失败，说明你和 getcomposer.org 之间有东西（比如改写 HTTPS 响应的代理）在改动文件。这条消息只针对下载：如果 `php.exe` 无法启动，安装会改为报告上面那条错误。

### `The code execution cannot proceed because VCRUNTIME140.dll was not found`

你自己启动 `php.exe` 时，如果该 PHP 缺少 Microsoft Visual C++ Redistributable，Windows 会显示这条提示。请从 [Microsoft](https://aka.ms/vs/17/release/vc_redist.x64.exe) 安装 x64 版（x86 版 PHP 则安装 `vc_redist.x86.exe`），然后重新运行 PHP。`vfox install` 会在安装过程中补装它。

### `Failed to install composer.`

插件无法用 `php.exe` 运行 Composer 的安装器。请先确认 PHP 能单独运行（`php -v`），以及 getcomposer.org 可以访问，然后重新安装。

## 链接机器上已有的安装

### `vfox link --detect` 找不到 PHP

插件会查看常见的位置，[机器上已有的安装](link.md)列出了这些位置。与系统其他软件共享的目录里的 PHP 会被有意跳过：例如发行版装在 `/usr/bin` 下的 PHP，链接它就等于链接整个系统。这样的安装请手动链接：`vfox link php@<版本> <包含 bin 的目录>`。

## 其他

### 安装过程中出现了别的问题

用 `vfox --debug install php@<version>` 运行安装。vfox 会打印它向插件询问了什么，以及插件怎样回答。报告问题时请附上这些输出，见[问题追踪](https://github.com/version-fox/vfox-php/issues)。
