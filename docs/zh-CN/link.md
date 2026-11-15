# 使用机器上已有的 PHP

[中文](link.md) | [English](../link.md)

如果机器上已经有 PHP，`vfox link --detect php` 会直接纳入它，而不是再编译一份。它可能来自 Homebrew、手工编译到 `/opt` 或 `/usr/local` 下的构建、版本管理器、Scoop、XAMPP 等 Windows 环境，或者 PATH 中的 PHP。它需要 vfox 1.1.0 或更新版本（`vfox --version`）。

```bash
vfox link --detect php
```

vfox 会列出插件找到的 PHP，你选择要链接的即可。`vfox link --detect -y php` 不再询问，直接链接全部。之后 `vfox use php@...` 的用法不变：`vfox list php` 会把已链接的版本标为 `(linked → <路径>)`，`vfox uninstall` 只删除链接，PHP 本身留在原处。

## 能找到什么

- Homebrew 的 keg：`/opt/homebrew/opt`、`/usr/local/opt` 和 Linuxbrew 下的 `php`、`php@X.Y`
- `/opt` 和 `/usr/local` 下名字以 `php` 开头的目录，例如 `/opt/php-8.4`
- 版本管理器 asdf、mise 和 phpenv 安装的 PHP
- macOS 上的 MAMP（`/Applications/MAMP/bin/php`）
- Windows 上：Scoop（`%USERPROFILE%\scoop\apps\php`）、XAMPP（`C:\xampp\php`）、Laragon、WampServer、Chocolatey、`C:\`、`C:\tools` 和 `C:\Program Files` 下名字以 `php` 开头的目录，以及 `C:\php`
- CI 运行器的工具缓存（`/opt/hostedtoolcache/PHP` 和 `C:\hostedtoolcache\windows\PHP`）
- PATH 中的 PHP，前提是它位于自己的目录里

## 会跳过什么

- 目录本身是共享的系统目录的 PHP，例如 `/usr`、`/usr/local`、`/opt`、`C:\` 或 Scoop 目录本身。链接它就等于链接整个系统，所以发行版装在 `/usr/bin` 下的 PHP 不会被提供。需要时请按下文手动链接。
- Scoop 的 shims，它们只是转发到真正的安装。
- vfox 自己管理的安装：`VFOX_HOME` 下的任何内容、插件自己的构建目录，以及 `.vfox` 目录下的任何内容。
- 不回应 `php -v` 的 PHP。

## 版本名

找到的 PHP 按 `vfox install` 的方式命名：版本号来自 `php -v`。在 Windows 上，NTS 构建会加上 `-nts`，因为插件安装的 TS 构建没有后缀；其他系统上，ZTS 构建会加上 `-zts`，因为插件安装的 NTS 构建没有后缀。同一版本若在多个路径中找到，只提供第一个路径。

## 手动链接

如果 `--detect` 没有找到，可以自己指定。路径是包含 `bin` 的目录（Windows 上是包含 `php.exe` 的目录）：

```bash
vfox link php@8.4.5 /opt/php-8.4.5
vfox use php@8.4.5
```

## 限制

- 链接的 PHP 按原样使用。插件会为它构建的 PHP 安装 Composer；被链接的 PHP 只有它自带的 Composer（如果有）。
- `vfox uninstall` 只删除链接，PHP 留在原处。
