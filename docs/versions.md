# Versions and names

[中文](zh-CN/versions.md) | [English](versions.md)

A version is what you write after `php@`. These are the forms the plugin accepts:

| You write | vfox installs | Where |
| --- | --- | --- |
| `latest` | the newest release | every platform |
| `8` | the newest 8.x.y | every platform |
| `8.4` | the newest 8.4.x | every platform |
| `8.4.5` | exactly 8.4.5 | every platform |
| `8.4.5-nts` | the NTS build of 8.4.5 | Windows only |
| `8.4.5-zts` | the thread-safe (ZTS) build of 8.4.5 | Linux and macOS only |

```shell
vfox install php@latest
vfox install php@8.4
vfox install php@8.4.5
vfox install php@8.4.5-nts
vfox install php@8.4.5-zts
```

## How a version is matched

The plugin sorts the releases newest first and takes the first one that matches:

1. A release that equals the version, `-nts` suffix included. An exact match always wins.
2. Otherwise the first release whose version starts with the version and a dot. So `8.4` takes the newest `8.4.x`, and `8` takes the newest `8.x.y`.

On Windows, a release that has both a TS and an NTS build lists the TS build first. So a line such as `8.4` picks the TS build, and only an explicit `-nts` picks NTS. `latest` is also the TS build.

On Linux and macOS, a plain version is the NTS build, and `-zts` builds the same release as a thread-safe PHP.

A version with a suffix other than `-nts` or `-zts` does not match, and neither does a line with a suffix: `8.4-nts` and `8.4-zts` are not versions. `-nts` is only a Windows release and `-zts` only a Linux and macOS build, so `8.4.5-nts` on Linux and macOS, and `8.4.5-zts` on Windows, are reported as not found.

## Where the lists come from

- **Linux and macOS:** the release index of php.net, for PHP 8, 7 and 5. Each release from 5.3.2 on counts when it has a source tarball. The tarball comes with a sha256 from php.net, and vfox checks the download against it. A `-zts` build is made from that tarball, so the list does not show it on its own.
- **Windows:** the builds on windows.php.net for your architecture: the current releases and the archive. Only x64 and x86 builds exist. Each release has a TS build and an NTS build.

## Searching

`vfox search php` lists the releases, newest first:

```text
Available versions:
 - 8.5.12
 - 8.5.11
```

If the list cannot be fetched, the plugin reports the address it tried. It does not return an empty list. Look at [troubleshooting](troubleshooting.md) for the message.

## Installed names

vfox names an installed PHP after its release: `8.5.12`, `8.5.12-nts` for an NTS build on Windows, or `8.5.12-zts` for a thread-safe build on Linux and macOS. `vfox list php` shows the installed names, and `vfox use php@8.5.12` takes the same names.

## Errors

- `PHP version not found: 8.4.9`: no release matches. Check the spelling against `vfox search php`.
- `No PHP releases found for windows/arm64`: PHP publishes no build for that architecture.
