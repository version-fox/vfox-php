# 变更记录

[中文](changes.md) | [English](../changes.md)

每个版本改了什么。日期以 UTC 计，是每个版本在 GitHub 上发布的那一天。0.3.0 之前的版本见 [GitHub Releases 页面](https://github.com/version-fox/vfox-php/releases)。

## Unreleased

- Linux 和 macOS：`bin/install` 只传入所构建的 PHP 版本所接受的 configure 选项，覆盖 PHP 5.3 到 8.5。此前每个版本都会传入全部选项。configure 会忽略它不认识的选项，但会发出警告，因此 PHP 8 的构建会打印 PHP 8 已不再有的选项的警告，例如 `--enable-wddx`、`--with-xmlrpc` 和 `--with-mysql`。构建得到的扩展不变。`--with-pear` 和 `--with-mhash` 仍会传入：PHP 会警告它们已弃用，但它们分别安装 PEAR 和 mhash 函数，插件一直如此。
- Windows：Visual C++ 运行库安装器的退出码改为从安装过程写出的文件中读取，因为 vfox 的 `os.execute` 只报告成功或失败。要求重启的安装（退出码 3010）不再导致安装失败；未签名的安装器、Windows 没有启动的安装器，以及 PowerShell 失败的专门提示也会重新显示。

## 0.3.3（2026-11-15）

- 开发：开发容器；Linux 和 Windows 的 Go 端到端套件，在容器里用 vfox 安装 PHP；CI 中的 lint、格式和 license 头检查；中英文文档。
- Linux：`bin/install` 在编译之前检查构建依赖：编译器、`make`、`autoconf`、`pkg-config` 和 `curl`，以及 configure 选项所用的库。缺少任何一项，安装会立即停止，消息会列出每个缺失的项目及其 Debian 或 Ubuntu 软件包。此前，安装要等到长时间编译之后才会在 configure 或 make 中失败。见[平台](platforms.md#linux)。
- Lua 和 shell 源文件带上了 Apache-2.0 的 license 头。
- Linux 和 macOS：PCRE JIT 默认开启，与 PHP 一致。`PHP_WITHOUT_PCRE_JIT` 用来关闭它。此前这个变量的判断条件写反了，构建默认关闭 JIT。
- Linux：gmp 和 sodium 通过系统的库缓存及其头文件查找，不再使用 `locate`。JPEG 和 PNG 来自系统的 libgd，因为构建使用 `--with-external-gd`，所以旧的 `--with-jpeg-dir` 和 `--with-png-dir` 选项已经去掉。
- Linux 和 macOS：Composer 安装器下载到 PHP 的 `bin` 目录，而不是安装开始时所在的目录。
- Linux 和 macOS：安装路径可以含有空格。PHP 在不含空格的目录里构建和安装，安装路径链接到该目录（见[平台](platforms.md#linux)）。此前 PHP 无法构建到这样的路径。`vfox uninstall` 通过新增的 `PreUninstall` 钩子删除构建目录。configure 参数逐个传递。
- Windows：安装路径可以含有空格，Composer 的各个步骤会给路径加引号。
- Windows：Composer 安装器在运行前会与 Composer 公布的 sha384 核对，与 Linux 和 macOS 一致。
- Windows：没有 Visual C++ 运行库时 `php.exe` 无法启动，此前安装会报告 sha384 不一致。现在，注册表未记录该运行库时，安装会补装 Microsoft Visual C++ 2015-2022 Redistributable：下载 Microsoft 的构建，核对它确由 Microsoft 签名，并在 Windows 询问是否允许后静默运行。然后运行 `php.exe`，如果它仍无法启动，安装停止（见[平台](platforms.md#windows)）。
- Windows：文件名带 rebuild 号的 NTS 构建（如 `8.5.12-1-nts`）现在会被列出，也能安装。
- 所有平台：`vfox link --detect php` 可以找到机器上已有的 PHP 安装，并链接你选择的那些。它通过 `Detect` 钩子实现，需要 vfox 1.1.0 或更新版本。见[机器上已有的安装](link.md)。
- Linux 和 macOS：`vfox install php@<版本>-zts` 用发布版本的源码构建线程安全（ZTS）的 PHP。不带后缀的版本仍是 NTS 构建。PHP 8.0 及以后用 `--enable-zts` 配置，PHP 5.x 和 7.x 用 `--enable-maintainer-zts` 配置。
- Linux、macOS 和 Windows：`vfox use` 给出版本系列或主版本时，选的是该发布版本的默认类型构建（即不带后缀的名字），和 `vfox install` 一致，不会选中 `-zts` 或 `-nts` 构建。要选它们，需要把名字写出来。

## 0.3.2（2026-09-12）

- 可选依赖的诊断信息（如 `gmp not found`）改为输出到 stderr，不再混进 configure 参数里。

## 0.3.1（2026-09-12）

- 恢复了 PHP 版本发现和平台安装。
- 发布改由共享的插件工作流完成。
- CI 在选择 PHP 之前先初始化 vfox，并校验 vfox 管理的 PHP。
- CI 不再保留空的旧版配置文件。

## 0.3.0（2025-09-29）

- Linux 支持 LTS 版本。
- 下载使用重定向后的 URL。
- 不使用 Homebrew 时，Linux 构建会在找到 gmp 和 sodium 的情况下把它们包括进来。
- 更新了 README。
