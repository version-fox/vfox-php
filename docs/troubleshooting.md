# Troubleshooting

[中文](zh-CN/troubleshooting.md) | [English](troubleshooting.md)

The messages below come from the plugin, from `bin/install`, or from vfox when the plugin fails. Each entry gives what the message means and what to do.

## `vfox requires hook support`

`vfox use -p` writes the project's PHP selection, and it needs vfox to be activated in the shell first. Activate it, then run the command:

```shell
eval "$(vfox activate bash)"          # bash or zsh
Invoke-Expression "$(vfox activate pwsh)"   # PowerShell
```

## `PHP version not found: <version>`

No release matches the version you wrote. Compare it with the list from `vfox search php`. Remember that `-nts` only exists on Windows, and that the NTS form needs a full release, `8.4.5-nts`, not `8.4-nts`. See [versions and names](versions.md).

## `No PHP releases found for windows/arm64`

PHP publishes no build for this architecture. On Windows on ARM there is nothing to install.

## `Failed to fetch PHP releases from <address>: ...`

The plugin could not read the release list. The address is the one it tried. Open it in a browser, or with `curl`, to see whether it is reachable. Behind a proxy, configure vfox's proxy as you would for any download. If the address answers, retry: a request that fails once often works the second time.

## Linux

### `Compilation Failure.`

The compile stopped, and the output above that message says where. The usual cause is a missing development package, such as `libxml2-dev` or `libonig-dev`. The package list is in [platforms](platforms.md#linux).

### `Installer corrupt`

The Composer installer did not match the sha384 that Composer publishes, so `bin/install` removed it and stopped. Run the install again. If the same thing happens each time, something between you and getcomposer.org is changing the file, such as a proxy.

## macOS

### `ERROR: Please install homebrew for OSX`

The build uses Homebrew for the libraries. Install it, then the formulae in [platforms](platforms.md#macos).

### `ERROR: PHP 8.0.30 requires openssl@1.1`

PHP 7.x and 8.0 need OpenSSL 1.1, which Homebrew no longer supplies through its normal formulae. Install a compatible OpenSSL 1.1, or set `PHP_CONFIGURE_OPTIONS` with the path to one. See [platforms](platforms.md#openssl).

### `gmp not found, not including in installation`

Information only. GMP is optional, so the build continues without it. Install `gmp` with Homebrew to enable it.

## Windows

### `The Composer installer does not match the sha384 that Composer publishes`

The installer that the plugin downloaded is not the one Composer publishes, so the install stopped before Composer was installed. Run the install again. If it fails every time, something between you and getcomposer.org is changing the file, such as a proxy that rewrites HTTPS responses.

### `The code execution cannot proceed because VCRUNTIME140.dll was not found`

The PHP builds need the Microsoft Visual C++ Redistributable, which the plugin does not install. Install it from Microsoft and run PHP again.

### `Failed to install composer.`

The plugin could not run Composer's installer with `php.exe`. Check that PHP runs on its own (`php -v`), and that getcomposer.org is reachable. Then install again.

## Other

### Something else went wrong during an install

Run the install with `vfox --debug install php@<version>`. vfox then prints what it asks the plugin and what the plugin answers. Include the output when you report a problem: see [the issue tracker](https://github.com/version-fox/vfox-php/issues).
