# 变更记录

[中文](changes.md) | [English](../changes.md)

每个版本改了什么。0.3.0 之前的版本见 [GitHub Releases 页面](https://github.com/version-fox/vfox-php/releases)。

## 未发布

- 开发：开发容器；Linux 和 Windows 的 Go 端到端套件，在容器里用 vfox 安装 PHP；CI 中的 lint、格式和 license 头检查；中英文文档。
- Lua 和 shell 源文件带上了 Apache-2.0 的 license 头。
- Linux 和 macOS：PCRE JIT 默认开启，与 PHP 一致。`PHP_WITHOUT_PCRE_JIT` 用来关闭它。此前这个变量的判断条件写反了，构建默认关闭 JIT。
- Linux：gmp 和 sodium 通过系统的库缓存及其头文件查找，不再使用 `locate`。JPEG 和 PNG 来自系统的 libgd，因为构建使用 `--with-external-gd`，所以旧的 `--with-jpeg-dir` 和 `--with-png-dir` 选项已经去掉。
- Linux 和 macOS：Composer 安装器下载到 PHP 的 `bin` 目录，而不是安装开始时所在的目录。
- Linux 和 macOS：安装路径含有空格时，会在编译之前被拒绝，并给出原因。PHP 的 `make install` 无法安装到这样的路径，此前的构建也没有检查这一点。configure 参数逐个传递。
- Windows：安装路径可以含有空格，Composer 的各个步骤会给路径加引号。
- Windows：Composer 安装器在运行前会与 Composer 公布的 sha384 核对，与 Linux 和 macOS 一致。
- Windows：文件名带 rebuild 号的 NTS 构建（如 `8.5.12-1-nts`）现在会被列出，也能安装。

## 0.3.2

- 可选依赖的诊断信息（如 `gmp not found`）改为输出到 stderr，不再混进 configure 参数里。

## 0.3.1

- 恢复了 PHP 版本发现和平台安装。
- 发布改由共享的插件工作流完成。
- CI 在选择 PHP 之前先初始化 vfox，并校验 vfox 管理的 PHP。
- CI 不再保留空的旧版配置文件。

## 0.3.0

- Linux 支持 LTS 版本。
- 下载使用重定向后的 URL。
- 不使用 Homebrew 时，Linux 构建会在找到 gmp 和 sodium 的情况下把它们包括进来。
- 更新了 README。
