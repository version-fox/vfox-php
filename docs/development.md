# Development

[中文](zh-CN/development.md) | [English](development.md)

## Layout

```
metadata.lua            plugin name, version, homepage, notes and the minimum vfox version
hooks/available.lua     vfox search: the list of releases
hooks/pre_install.lua   vfox install: choose the release, return its URL, name and checksum
hooks/post_install.lua  after the download: compile PHP on Linux and macOS; on Windows, install the Visual C++ runtime when it is missing, write php.ini and install Composer
hooks/env_keys.lua      PATH of the selected PHP
hooks/pre_use.lua       vfox use: the installed PHP that a version names; a line takes its default build
hooks/detect.lua        vfox link --detect php: finds the PHP installs already on the machine
hooks/pre_uninstall.lua vfox uninstall: removes the build behind an install path that holds a space
lib/detect_php.lua      where PHP installs are looked for, and how they are named
lib/releases.lua        the release lists: php.net on Linux and macOS, windows.php.net on Windows
lib/constants.lua       the URLs of those lists
lib/util.lua            version comparison and file helpers
lib/php_build.lua       builds PHP and installs Composer on Linux and macOS
tests/*_test.lua        offline hook and build tests, run with glua
tests/e2e/              the container suites and the Go checks of the repository, see e2e.md
Injection.lua           type hints for what vfox injects; never loaded
.devcontainer/          the dev container
.github/workflows/      CI
docs/, README*.md       the documentation; the Chinese pages are in docs/zh-CN/ and README_CN.md
```

vfox loads `metadata.lua`, calls a hook when a command needs it, and puts `PLUGIN` and `RUNTIME` (`osType`, `archType`, `version`, `pluginDirPath`) in scope. `osType` and `archType` are Go's `GOOS` and `GOARCH` of the vfox binary.

## What runs for a command

| You run | Hook | What it does |
| --- | --- | --- |
| `vfox search php` | `Available` | lists the releases, from `lib/releases.lua` |
| `vfox install php@8.4` | `PreInstall` | resolves the version; returns the URL, the install name and, on Linux and macOS, the sha256 |
| (after the download) | `PostInstall` | Linux and macOS: builds PHP with `lib/php_build.lua`; Windows: installs the Visual C++ runtime when the registry does not record it, writes `php.ini` and installs Composer |
| `vfox use php@8.4` | `PreUse` | the installed name that the version selects, from `hooks/pre_use.lua`; a line takes its default build |
| `vfox use php@8.4` | `EnvKeys` | sets `PATH` to the `bin` folder of the install; on Windows, to the install folder itself |
| `vfox info php` | none | vfox prints the notes from `metadata.lua`, which link the README |
| `vfox link --detect php` | `Detect` | lists the PHP installs already on the machine, from `lib/detect_php.lua`; linking one leaves it where it is |

## Contracts that cost time to find

- `PreInstall` returns `version`, which becomes the install's name, and `url`. On Linux and macOS it also returns `sha256`, and vfox checks the download against it. The Windows builds come with no checksum here, so vfox has nothing to check.
- `PostInstall` reads `ctx.sdkInfo['php']`, for its `path` and `version`. `CompileInstallPHP` takes the `x.y.z` release, and `-zts` on the name asks for a thread-safe build (`php_build.install` with `zts` set). Anything else fails.
- An unknown version is refused by name: `PHP version not found: <version>`. The E2E suites check that message.
- `lib/releases.lua` fails with `No PHP releases found for <os>/<arch>` when a platform has no builds, which is how Windows on ARM reports itself.
- The Windows list has a TS and an NTS entry for each release. The TS entry sorts first, which is why a line picks TS and `latest` is TS.
- `PreUse` returns the installed name, or the version as typed when nothing installed matches. Returning nil would leave the choice to vfox's prefix match over all installed names, which would take a `-zts` build for `8.4`.

## Tests

The offline tests run in the Test Plugin workflow. The Lua tests run on Ubuntu, and `php_build_brew_test.lua` runs on macOS against its Homebrew. You can run them the same way:

```shell
go run github.com/yuin/gopher-lua/cmd/glua@v1.1.1 tests/hooks_test.lua
go run github.com/yuin/gopher-lua/cmd/glua@v1.1.1 tests/windows_test.lua
go run github.com/yuin/gopher-lua/cmd/glua@v1.1.1 tests/post_install_test.lua
go run github.com/yuin/gopher-lua/cmd/glua@v1.1.1 tests/pre_uninstall_test.lua
go run github.com/yuin/gopher-lua/cmd/glua@v1.1.1 tests/detect_test.lua
go run github.com/yuin/gopher-lua/cmd/glua@v1.1.1 tests/php_build_test.lua
```

`hooks_test.lua` replaces the HTTP client, the JSON and HTML modules and the file functions, then checks what the hooks return, including the Windows release list with its NTS builds, and what `PreUse` picks among the installed names. `windows_test.lua` checks the Windows install: the runtime (the registry query, the download, the signature check of the installer, its exit codes, and the x86 record), the php.ini, the Composer installer and its sha384 check, and the quoting of paths that hold spaces. `post_install_test.lua` checks the Linux and macOS compile step: what it asks the build for, and the versions it refuses. `pre_uninstall_test.lua` checks the step that removes a PHP build. `php_build_test.lua` checks the build on a fake machine: the options of each PHP version, the macOS formulae and the OpenSSL that it picks, the Linux build dependencies and the packages that provide them, the build directory of an install path with spaces, the steps of a build and the removal of a failed one, and Composer. The fake machine answers the commands that check it, and records the commands that build PHP. `php_build_brew_test.lua` checks the options against the Homebrew of a Mac, and does nothing on other systems. `detect_test.lua` checks which PHP installs on the machine are found, how they are named, and which are left alone: shared system folders, shims, vfox's own installs, and a PHP that does not answer `php -v`. The container suites are described in [E2E tests](e2e.md).

## Local checks

These are the checks CI runs. The dev container carries the pinned versions; elsewhere, install the same ones:

```shell
stylua --check .                                # Lua formatting (stylua 2.5.2); `stylua .` formats
lua-language-server --check . --checklevel=Warning
cd tests/e2e
gofmt -l .                                      # prints nothing when formatted
go vet ./...
go test -short ./...                            # unit tests, including the documentation checks
cd ../..
actionlint                                      # the workflows (actionlint 1.7.12)
license-eye header check                        # license headers (SkyWalking Eyes 0.9.0)
addlicense -check -f .license.tpl tests/e2e/windows/*.ps1
```

`go test -short` checks the documentation as well: both folders have the same pages, each page links to its other language, and every relative link points at a file that exists. It also checks that the notes `vfox info php` prints link the README.

## Releasing

Maintainers publish from **Actions → Plugin → Run workflow** on the default branch, entering a stable plugin version without the `v` prefix. The shared workflow updates `metadata.lua`, creates the version commit and tag, and publishes the ZIP and the manifest in this repository. No local tag or extra release token is needed. Pull requests run the checks only.

Pushing a version tag publishes too, when `PLUGIN.version` already matches the tag. If publication fails, re-run the failed job to resume it.

The workflow follows the shared `@v1` release tool, and updating that tool does not release this plugin. The [shared workflow documentation](https://github.com/version-fox/plugin-manifest-action) has the package contract and the requirements of a first rollout.

## Writing the docs

English pages are in `docs/`, the Chinese ones in `docs/zh-CN/` under the same names, and the Chinese README is `README_CN.md`. Each page starts with a line that links to the other language. A new page goes into the Documentation list of both READMEs. The notes that `vfox info php` prints link to `README.md`, so the README keeps the links those notes need. Run `go test -short ./...` after you change the docs.
