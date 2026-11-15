# E2E 测试

[中文](e2e.md) | [English](../e2e.md)

端到端套件在容器里用 vfox 安装 PHP，检查的是用户会检查的内容。它们是 `tests/e2e` 里的 Go 测试：`linux` 和 `windows` 各自为每个 PHP 版本运行一个容器，`common` 放两者共用的部分。

离线的 Lua 和 shell 测试在 Test Plugin 工作流中运行，见[开发](development.md)。

## 在哪里运行

| 平台 | Runner | 运行方式 |
| --- | --- | --- |
| Linux amd64 | `ubuntu-latest` | Go 测试，使用 runner 上的 Docker |
| Linux arm64 | `ubuntu-26.04-arm` | 同上 |
| Windows x64 | `windows-latest` | Go 测试，使用 runner 上 Windows 容器模式的 Docker |
| macOS | `macos-latest` | 不用容器：工作流直接在 runner 上安装 PHP |

E2E 工作流会在拉取请求、推送到 `main`、每周一次以及手动触发时运行。

## 开发容器

`.devcontainer/` 会打开一个带有固定版本工具的 Linux 环境：Go 1.27.1、Docker CLI、stylua 2.5.2、lua-language-server 3.19.1、vfox 1.1.0（用其 sha256 校验）、license-eye 0.9.0、addlicense 1.2.0、actionlint 1.7.12，以及构建 PHP 需要的软件包。宿主机的 Docker 套接字会被挂载进来，所以套件在宿主机的守护进程上启动容器，即 Docker-out-of-Docker。

用任何支持 Dev Containers 的工具打开即可：VS Code 中的 **Dev Containers: Reopen in Container**，或者命令行：

```shell
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash
```

使用 rootless Docker 的用户，请在打开容器之前在宿主机上导出 `DOCKER_SOCK="$XDG_RUNTIME_DIR/docker.sock"`。

`TESTCONTAINERS_RYUK_DISABLED=true` 已预先设置。Ryuk 会在宿主机的守护进程上发布一个端口，并等待套件回连它，而 Docker-out-of-Docker 的容器做不到这一点，所以套件会自己终止每个容器。

Windows 没有开发容器，因为 Dev Containers 规范不支持 Windows 容器镜像。Windows 需要在 Windows 宿主机上直接运行。

## 环境变量

| 变量 | 默认值 | 含义 |
| --- | --- | --- |
| `PHP_VERSION` | `latest 8.3` | 要安装的 PHP 版本，用空格分隔；每一项可以是 `latest`、主版本、主.次版本或完整版本 |
| `E2E_MAX_JOBS` | `2` | 同时运行的容器数 |
| `E2E_RETRY_ATTEMPTS` | `3` | `vfox search` 的尝试次数，每次失败后等待 10 秒的递增时间 |
| `MAKEFLAGS` | `-j2` | Linux 容器内的编译并行度；宿主机上设置的值会传入容器 |

## Linux

在开发容器里，或者在任何装有 Docker 和 Go 1.27.1 的主机上：

```shell
cd tests/e2e
go test -v -timeout 55m -run TestE2E ./linux
PHP_VERSION=latest MAKEFLAGS=-j8 go test -v -timeout 55m -run TestE2E ./linux
```

第二行只运行一个版本，速度更快。镜像由 `tests/e2e/linux/Dockerfile` 构建，它把检出目录作为 CI 制作的那种插件压缩包带进去。每个容器都从源码编译自己的 PHP，需要几分钟。

## Windows

Windows 容器需要一台开启了 Windows 容器模式 Docker 的 Windows 宿主机，以及 Go 1.27.1。该套件使用 x64。基础镜像是 `mcr.microsoft.com/windows/servercore:ltsc2025-KB5122871-amd64`，它的 Windows 版本必须与宿主机一致，因为进程隔离要求如此。

```powershell
cd tests\e2e
go test -v -timeout 55m -run TestE2E .\windows
```

## 套件检查什么

对每个 PHP 版本，按以下顺序检查：

1. **插件**：`vfox add -s` 安装压缩包，`vfox info php` 链接到 README。
2. **未知版本**：`vfox install php@99.0.0` 失败，并且报出版本号：`PHP version not found: 99.0.0`。
3. **安装**：`vfox install` 成功。在 Linux 上，其输出中会有 `Verifying checksum`，因为 PreInstall 传入了 php.net 的 sha256。
4. **选择**：`vfox use -p` 选中该版本。在 Linux 上，`php` 解析为项目里的 `.vfox/sdks/php/bin/php`，并且 `PHP_VERSION` 与请求的版本匹配。
5. **Linux 上的运行时**：`php -v` 的开头是该发布版本，`php -m` 列出 `bin/install` 启用的模块（见 `tests/e2e/common/common.go` 中的 `LinuxModules`，其中包括镜像里安装了的 gmp 和 sodium），PCRE JIT 已开启（含空格的运行中为 `not compiled in`，即构建时传入了 `--without-pcre-jit`），gd 报告支持 JPEG，`bin/` 旁边有 `conf.d/php.ini`，`composer -V` 与 `pear version` 能运行，`vfox list` 显示该版本。
6. **Windows 上的运行时**：同样的版本横幅检查，另外还有：TS 构建的 `PHP_ZTS` 为 1，已加载 `openssl`，PHP 加载的 `php.ini` 就是插件写入的那个，`extension_dir` 是绝对路径，`composer.bat` 能运行。套件以 `VFOX_HOME=C:\vfox home` 运行，这个路径含有空格，所以安装路径的引号处理也会被测试。
7. **Windows 上的 NTS**：在单独的项目中执行 `vfox install php@<version>-nts`，其 `PHP_ZTS` 为 0。
8. **搜索**：`vfox search php` 列出该版本。列表从网络获取，所以会重试。

在 Linux 上，另外还有一次运行使用含空格的 `VFOX_HOME`（`/root/vfox home`），并且构建时关闭了 PCRE JIT。它执行与其他运行相同的检查，还会检查安装路径是否链接到不含空格的构建目录，以及 `vfox uninstall` 是否同时删除了链接和构建目录。

## 本地检查

lint、格式和 license 检查在开发容器里运行，命令见[开发](development.md#本地检查)。没有这些工具的主机上，license 检查也可以用容器运行：

```shell
docker run --rm -v "$PWD:/src" ghcr.io/google/addlicense:v1.2.0 -check -f .license.tpl tests/e2e/windows/*.ps1
```

## 已知缺口

- Linux arm64 任务和 Windows 任务只在 CI 中运行。开发容器覆盖的是 Linux amd64，而 Windows 套件需要 Windows 宿主机。
- macOS 任务直接在 runner 上安装 PHP，所以 macOS 上的 OpenSSL 选择只在那里被覆盖。
- 套件测试的是镜像里的 vfox 发布版本，而不是 `main` 分支。
