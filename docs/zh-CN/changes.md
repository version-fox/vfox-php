# 变更记录

[中文](changes.md) | [English](../changes.md)

每个版本改了什么。0.3.0 之前的版本见 [GitHub Releases 页面](https://github.com/version-fox/vfox-php/releases)。

## 未发布

- 开发：开发容器；Linux 和 Windows 的 Go 端到端套件，在容器里用 vfox 安装 PHP；CI 中的 lint、格式和 license 头检查；中英文文档。
- Lua 和 shell 源文件带上了 Apache-2.0 的 license 头。行为没有变化。

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
