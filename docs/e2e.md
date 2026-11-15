# E2E tests

[中文](zh-CN/e2e.md) | [English](e2e.md)

The end-to-end suites install PHP with vfox inside containers, and check what a user would check. They are Go tests in `tests/e2e`: `linux` and `windows` each run one container per PHP version, and `common` holds what the two share. The Linux suite runs one more container, for `8.3.12-zts`, the thread-safe build, which Windows does not have. In that container, `vfox use` of the line `8.3` must fail as not installed, so the line does not take the thread-safe build.

The offline Lua tests and the Go tests of `bin/install` run in the Test Plugin workflow, described in [development](development.md).

## Where they run

| Platform | Runner | How |
| --- | --- | --- |
| Linux amd64 | `ubuntu-latest` | Go test, on the runner's Docker |
| Linux arm64 | `ubuntu-26.04-arm` | the same |
| Windows x64 | `windows-latest` | Go test, on the runner's Docker in Windows-container mode |
| macOS | `macos-latest` | no containers: the workflow installs PHP on the runner |

The E2E workflow runs on pull requests, on pushes to `main`, once a week and on demand.

## Dev container

`.devcontainer/` opens a Linux environment with the pinned tools: Go 1.27.1, the Docker CLI, stylua 2.5.2, lua-language-server 3.19.1, vfox 1.1.0 (checked against its sha256), license-eye 0.9.0, addlicense 1.2.0, actionlint 1.7.12, and the packages a PHP build needs. The host's Docker socket is mounted, so the suites start their containers on the host's daemon, Docker-out-of-Docker.

Open it with any Dev Containers tool: **Dev Containers: Reopen in Container** in VS Code, or the CLI:

```shell
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash
```

Rootless Docker users export `DOCKER_SOCK="$XDG_RUNTIME_DIR/docker.sock"` on the host before they open the container.

`TESTCONTAINERS_RYUK_DISABLED=true` is preset. Ryuk publishes a port on the host daemon and waits for the suite to dial it back, which a Docker-out-of-Docker container cannot do, so the suites terminate every container themselves.

There is no dev container for Windows, because the Dev Containers specification does not support Windows container images. Windows runs natively on a Windows host.

## Environment

| Variable | Default | Meaning |
| --- | --- | --- |
| `PHP_VERSION` | `latest 8.3` | the PHP versions to install, separated by spaces; each is `latest`, a major, a major.minor or a full release |
| `E2E_MAX_JOBS` | `2` | containers that run at once |
| `E2E_RETRY_ATTEMPTS` | `3` | attempts for `vfox search`, with a backoff of 10 seconds per attempt |
| `MAKEFLAGS` | `-j2` | build parallelism inside the Linux containers; a value set on the host is passed through |

## Linux

In the dev container, or on any host with Docker and Go 1.27.1:

```shell
cd tests/e2e
go test -v -timeout 55m -run TestE2E ./linux
PHP_VERSION=latest MAKEFLAGS=-j8 go test -v -timeout 55m -run TestE2E ./linux
```

The second line runs one version, which is faster. The image is built from `tests/e2e/linux/Dockerfile`, and it carries the checkout as the plugin archive that CI makes. Each container compiles its PHP from source, which takes a few minutes.

## Windows

Windows containers need a Windows host with Docker in Windows-container mode, and Go 1.27.1. The suite is x64. The base image is `mcr.microsoft.com/windows/servercore:ltsc2025-KB5122871-amd64`, and its Windows build must match the host's, because process isolation requires it.

```powershell
cd tests\e2e
go test -v -timeout 55m -run TestE2E .\windows
```

## What the suites check

For each PHP version, in this order:

1. **Plugin:** `vfox add -s` installs the archive, and `vfox info php` links the README.
2. **Unknown version:** `vfox install php@99.0.0` fails and names the version: `PHP version not found: 99.0.0`.
3. **Install:** `vfox install` succeeds. On Linux, its output shows `Verifying checksum`, because PreInstall passes php.net's sha256. On Windows, the image has no Visual C++ runtime: before the install, no folder on the loader's search path holds `vcruntime140.dll`, and after it, `System32` does, because the plugin installed the runtime.
4. **Selection:** `vfox use -p` selects the version. On Linux, `php` resolves to `.vfox/sdks/php/bin/php` in the project, and `PHP_VERSION` matches the version asked for.
5. **Runtime on Linux:** `php -v` starts with the release, `php -m` lists the modules that `bin/install` enables (`LinuxModules` in `tests/e2e/common/common.go`, including gmp and sodium, which the image installs), PCRE JIT is enabled (`not compiled in` in the spaced run, which passes `--without-pcre-jit`), `PHP_ZTS` is 1 in the `-zts` container and 0 in the others, gd reports JPEG support, `conf.d/php.ini` is there next to `bin/`, `composer -V` and `pear version` run, and `vfox list` shows the version.
6. **Runtime on Windows:** the same banner check, with `PHP_ZTS` equal to 1 for the TS build, `openssl` loaded, the `php.ini` the plugin wrote as the one PHP loads, an absolute `extension_dir`, and `composer.bat` working. The suite runs with `VFOX_HOME` set to `C:\vfox home`, a path with a space, so the quoting of install paths is tested.
7. **NTS on Windows:** `vfox install php@<version>-nts` in a project of its own, where `PHP_ZTS` is 0. The runtime is recorded by now, so this install does not install it again.
8. **Search:** `vfox search php` lists the version, with retries, since the list is fetched from the network.

On Linux, one more run uses a `VFOX_HOME` with a space, `/root/vfox home`, and builds PHP without PCRE JIT. It runs the same checks as the other runs. It also checks that the install path links to a build directory without spaces, and that `vfox uninstall` removes both the link and the build directory. The run then copies its PHP to `/opt/php-system`, uninstalls vfox's copy, and checks that `vfox link --detect -y php` links the copy, that vfox runs it, and that uninstalling the link leaves the copy in place. The Windows suite does the same with the TS build in `C:\php-system`, for each PHP version.

## Local checks

The lint, format and license checks run in the dev container, and the commands are in [development](development.md#local-checks). The license checks also run as containers, on a host without the tools:

```shell
docker run --rm -v "$PWD:/src" ghcr.io/google/addlicense:v1.2.0 -check -f .license.tpl tests/e2e/windows/*.ps1
```

## Known gaps

- The Linux arm64 job and the Windows job run only in CI. The dev container covers Linux amd64, and the Windows suite needs a Windows host.
- The macOS job installs PHP on the runner. The Test Plugin job checks `bin/install` against the runner's Homebrew, which Linux does not have.
- The suites test one vfox release, the one in the image, not `main`.
