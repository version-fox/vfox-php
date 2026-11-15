# vfox-php

[中文](README_CN.md) | [English](README.md)

[vfox](https://vfox.dev/) 的 [PHP](https://www.php.net/) 插件。

在 Linux 和 macOS 上，它从 php.net 的源码发布包编译 PHP；在 Windows 上，它下载 windows.php.net 的预编译版本。每次安装都会附带 Composer。

## 安装

先安装 [vfox](https://github.com/version-fox/vfox)，然后添加插件、安装 PHP 并选中它：

```shell
vfox add php
vfox search php
vfox install php@latest
vfox use --global php@latest
php -v
```

`php -v` 会显示当前选中的 PHP。要让 `php` 出现在 `PATH` 里，需要把 vfox 挂载到 Shell，见 vfox 的[快速入门](https://vfox.dev/zh-hans/guides/quick-start.html)。

## 版本

版本可以是一个完整的发布版本、一个版本系列（如 `8.4`），或者 `latest`：

```shell
vfox install php@latest     # 最新发布版本
vfox install php@8.4        # 最新的 8.4.x
vfox install php@8.4.5      # 精确到 8.4.5
vfox install php@8.4.5-nts  # 仅 Windows：8.4.5 的 NTS 版本
vfox install php@8.4.5-zts  # 仅 Linux 和 macOS：8.4.5 的 ZTS（线程安全）版本
```

在 Windows 上，不带后缀的版本是线程安全（TS）版本，`-nts` 选择非线程安全（NTS）版本。在 Linux 和 macOS 上，不带后缀的版本是 NTS 版本，`-zts` 选择线程安全版本。版本如何匹配、列表来自哪里，以及可能看到的错误，见 [docs/zh-CN/versions.md](docs/zh-CN/versions.md)。

## 前置条件

在 Linux 和 macOS 上安装 PHP 需要一些依赖：编译器，以及 PHP 编译时要链接的开发库。每个系统需要的软件包见 [docs/zh-CN/platforms.md](docs/zh-CN/platforms.md)。在 Windows 上，构建需要 Microsoft Visual C++ 2015-2022 Redistributable（x64；x86 版 PHP 需要 x86 版），插件不会安装它。见 [docs/zh-CN/platforms.md](docs/zh-CN/platforms.md#windows)。

## 平台

- **Linux 和 macOS** 编译源码发布包。CI 运行的架构：Linux amd64 和 arm64。
- **Windows** 下载 x64 和 x86 的预编译版本。PHP 没有提供 Windows ARM64 版本，所以 Windows on ARM 上没有可以安装的版本。

## 文档

**使用插件**

- [版本与命名](docs/zh-CN/versions.md)：版本如何匹配、列表从哪里来，以及可能出现的错误
- [机器上已有的安装](docs/zh-CN/link.md)：`vfox link --detect php` 纳入已经安装好的 PHP
- [平台](docs/zh-CN/platforms.md)：每个系统构建或下载什么，需要什么
- [构建选项](docs/zh-CN/configuration.md)：改变 PHP 构建方式的环境变量
- [问题排查](docs/zh-CN/troubleshooting.md)：可能看到的提示，以及对应的处理方法
- [变更记录](docs/zh-CN/changes.md)：每个版本改了什么

**参与开发**

- [从源码安装](docs/zh-CN/install-from-source.md)：在发布之前试用本仓库的检出版本
- [开发](docs/zh-CN/development.md)：插件的工作方式、检查项和发布流程
- [E2E 测试](docs/zh-CN/e2e.md)：容器测试与开发容器
