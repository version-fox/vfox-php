# 开发

[中文](development.md) | [English](../development.md)

## 目录结构

```
metadata.lua            插件名、版本、主页、提示信息和最低 vfox 版本
hooks/available.lua     vfox search：发布版本列表
hooks/pre_install.lua   vfox install：选定发布版本，返回 URL、安装名，以及 Linux 和 macOS 上的 sha256
hooks/post_install.lua  下载之后：Linux 和 macOS 上编译 PHP；Windows 上缺少运行库时安装它，再写入 php.ini 并安装 Composer
hooks/env_keys.lua      选中 PHP 的 PATH
hooks/pre_use.lua       vfox use：版本对应的已安装 PHP；版本系列取默认类型的构建
hooks/detect.lua        vfox link --detect php：找出机器上已有的 PHP 安装
hooks/pre_uninstall.lua vfox uninstall：删除含空格安装路径背后的构建目录
lib/detect_php.lua      在哪里查找 PHP 安装，以及如何为它们命名
lib/releases.lua        发布列表：Linux 和 macOS 来自 php.net，Windows 来自 windows.php.net
lib/constants.lua       那些列表的 URL
lib/util.lua            版本比较和文件辅助函数
lib/php_build.lua       在 Linux 和 macOS 上编译 PHP、安装 Composer
tests/*_test.lua        离线的 hook 和构建测试，用 glua 运行
tests/e2e/              容器端到端套件，以及仓库的 Go 检查，见 e2e.md
Injection.lua           vfox 注入对象的类型提示，从不加载
.devcontainer/          开发容器
.github/workflows/      CI
docs/、README*.md       文档；中文页面在 docs/zh-CN/ 和 README_CN.md
```

vfox 会加载 `metadata.lua`，在某个命令需要时调用对应的 hook，并把 `PLUGIN` 和 `RUNTIME`（`osType`、`archType`、`version`、`pluginDirPath`）放进作用域。`osType` 和 `archType` 是运行 vfox 的程序的 Go `GOOS` 与 `GOARCH`。

## 每个命令会运行什么

| 你运行 | Hook | 作用 |
| --- | --- | --- |
| `vfox search php` | `Available` | 列出发布版本，来自 `lib/releases.lua` |
| `vfox install php@8.4` | `PreInstall` | 解析版本，返回 URL、安装名，以及 Linux 和 macOS 上的 sha256 |
| （下载之后） | `PostInstall` | Linux 和 macOS：由 `lib/php_build.lua` 编译 PHP；Windows：注册表未记录运行库时安装它，再写入 `php.ini` 并安装 Composer |
| `vfox use php@8.4` | `PreUse` | 返回版本对应的已安装名字；版本系列取默认类型的构建，来自 `hooks/pre_use.lua` |
| `vfox use php@8.4` | `EnvKeys` | 把 `PATH` 设为安装目录下的 `bin`；Windows 上设为安装目录本身 |
| `vfox info php` | 无 | vfox 打印 `metadata.lua` 中的提示信息，其中有指向 README 的链接 |
| `vfox link --detect php` | `Detect` | 列出机器上已有的 PHP 安装，来自 `lib/detect_php.lua`；链接它不会移动安装 |

## 那些要花时间才能找到的约定

- `PreInstall` 返回 `version`（它会成为安装的名字）和 `url`。在 Linux 和 macOS 上，它还返回 `sha256`，vfox 用它校验下载的文件。Windows 的构建这里没有校验和，所以 vfox 没有可以校验的内容。
- `PostInstall` 读取 `ctx.sdkInfo['php']` 中的 `path` 和 `version`。`CompileInstallPHP` 接受 `x.y.z` 形式的发布版本，名字上的 `-zts` 表示线程安全构建（即 `php_build.install` 的 `zts` 参数），其他形式都会失败。
- 未知版本会被按名字拒绝：`PHP version not found: <version>`。端到端套件会检查这条消息。
- 某个平台没有任何构建时，`lib/releases.lua` 会报 `No PHP releases found for <os>/<arch>`，Windows on ARM 就是这样报错的。
- Windows 列表中每个发布版本都有 TS 和 NTS 两项。TS 排在前面，所以版本系列选的是 TS，`latest` 也是 TS。
- `PreUse` 返回已安装的名字；没有匹配时返回用户写的版本。返回 nil 就会交给 vfox 对所有已安装名字做前缀匹配，那样 `8.4` 可能选中 `-zts` 构建。

## 测试

离线测试在 Test Plugin 工作流中运行：Lua 测试在 Ubuntu 上运行，`php_build_brew_test.lua` 在 macOS 上对照其 Homebrew 运行。你也可以在本地用同样的方式运行：

```shell
go run github.com/yuin/gopher-lua/cmd/glua@v1.1.1 tests/hooks_test.lua
go run github.com/yuin/gopher-lua/cmd/glua@v1.1.1 tests/windows_test.lua
go run github.com/yuin/gopher-lua/cmd/glua@v1.1.1 tests/post_install_test.lua
go run github.com/yuin/gopher-lua/cmd/glua@v1.1.1 tests/pre_uninstall_test.lua
go run github.com/yuin/gopher-lua/cmd/glua@v1.1.1 tests/detect_test.lua
go run github.com/yuin/gopher-lua/cmd/glua@v1.1.1 tests/php_build_test.lua
```

`hooks_test.lua` 会替换 HTTP 客户端、JSON 和 HTML 模块以及文件函数，然后检查 hook 的返回值，包括带 NTS 构建的 Windows 发布列表，以及 `PreUse` 在已安装名字中的选择。`windows_test.lua` 检查 Windows 上的安装：运行库（注册表查询、下载、安装器的签名核对、退出码以及 x86 的记录）、php.ini、Composer 安装器及其 sha384 校验，以及带空格路径的引号。`post_install_test.lua` 检查 Linux 和 macOS 的编译步骤：向构建要求什么，以及拒绝哪些版本。`pre_uninstall_test.lua` 检查删除 PHP 构建的步骤。`php_build_test.lua` 在假机器上检查构建（`lib/php_build.lua`）：各 PHP 版本的选项、macOS 的 formula 及选中的 OpenSSL、Linux 的构建依赖及提供它们的软件包、带空格安装路径的构建目录、构建的各个步骤和失败后的清理，以及 Composer。假机器回答检查机器的命令，并记录编译 PHP 的命令。`php_build_brew_test.lua` 在 Mac 上把选项与 Homebrew 对照，在其他系统上什么也不做。`detect_test.lua` 检查能找到机器上哪些 PHP 安装、如何为它们命名，以及哪些不纳入：共享的系统目录、shims、vfox 自己的安装，以及不回应 `php -v` 的 PHP。容器套件见 [E2E 测试](e2e.md)。

## 本地检查

以下是 CI 运行的检查。开发容器里已经装好了固定版本；在其他环境里，请安装同样的版本：

```shell
stylua --check .                                # Lua 格式（stylua 2.5.2）；`stylua .` 用于格式化
lua-language-server --check . --checklevel=Warning
cd tests/e2e
gofmt -l .                                      # 没有输出即为格式正确
go vet ./...
go test -short ./...                            # 单元测试，包括文档检查
cd ../..
actionlint                                      # 工作流（actionlint 1.7.12）
license-eye header check                        # license 头（SkyWalking Eyes 0.9.0）
addlicense -check -f .license.tpl tests/e2e/windows/*.ps1
```

`go test -short` 同样检查文档：两个目录的页面一一对应，每个页面都链接到另一种语言，每个相对链接都指向一个存在的文件。它还检查 `vfox info php` 打印的提示信息是否链接到 README。

## 发布

维护者在默认分支上依次选择 **Actions → Plugin → Run workflow**，输入不带 `v` 前缀的稳定插件版本号。共享工作流会更新 `metadata.lua`，创建版本提交和标签，并在本仓库发布 ZIP 和 manifest。不需要本地标签，也不需要额外的发布令牌。拉取请求只运行检查。

推送版本标签同样会发布，前提是 `PLUGIN.version` 已与标签一致。发布失败时，重新运行失败的任务即可继续。

该工作流跟随共享的 `@v1` 发布工具，更新该工具并不会发布本插件。包的约定和首次发布的要求见[共享工作流文档](https://github.com/version-fox/plugin-manifest-action)。

## 编写文档

英文页面在 `docs/` 中，中文页面在 `docs/zh-CN/` 中，文件名相同，中文 README 是 `README_CN.md`。每个页面开头都有一行指向另一种语言的链接。新页面要加入两份 README 的文档列表。`vfox info php` 打印的提示信息链接到 `README.md`，所以 README 要保留这些链接所需的内容。修改文档后，请运行 `go test -short ./...`。
