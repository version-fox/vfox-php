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

No release matches the version you wrote. Compare it with the list from `vfox search php`. Remember that `-nts` only exists on Windows and `-zts` only on Linux and macOS, and that either suffix needs a full release, such as `8.4.5-zts`, not `8.4-zts`. See [versions and names](versions.md).

## `No PHP releases found for windows/arm64`

PHP publishes no build for this architecture. On Windows on ARM there is nothing to install.

## `Failed to fetch PHP releases from <address>: ...`

The plugin could not read the release list. The address is the one it tried. Open it in a browser, or with `curl`, to see whether it is reachable. Behind a proxy, configure vfox's proxy as you would for any download. If the address answers, retry: a request that fails once often works the second time.

## Linux and macOS

### `Failed to remove the PHP build behind <path>`

`vfox uninstall` could not remove the build directory that the install path links to. The build directory is under `~/.local/share/vfox-php/builds`, or under `/var/tmp` for a home directory with a space. Check the permissions of that directory, remove it by hand, and run the uninstall again. See [platforms](platforms.md#linux).

### `links to <target>, which is not a vfox-php build directory`

The install path is a link, but to a directory that the plugin did not make, so `vfox uninstall` leaves that directory alone and stops. Check the link with `ls -l`, and remove the link by hand if it is not wanted.

## Linux

### `ERROR: PHP cannot be built, because these build dependencies are missing`

`bin/install` found tools or libraries that the build needs and the system does not have. It stopped before it moved the source or compiled anything. The lines under the message name each missing item, and the `sudo apt-get install` line names the Debian or Ubuntu packages that provide them. Install those packages and run `vfox install` again. On other systems, install the equivalent packages. The full list is in [platforms](platforms.md#linux).

### `Compilation Failure.`

The compile stopped, and the output above that message says where. The build checks for missing packages before it starts, so a missing package now usually stops the install with the message above instead.

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

### `The Visual C++ Redistributable is not installed, and it could not be downloaded`

The plugin downloads the Microsoft Visual C++ 2015-2022 Redistributable from aka.ms when the registry does not record it. The download failed, so the install stopped before it wrote anything. Check the connection and any proxy, then install again. To install the build yourself, use the x64 build from [Microsoft](https://aka.ms/vs/17/release/vc_redist.x64.exe), or `vc_redist.x86.exe` for x86 PHP, then install PHP again. The message names the build for your PHP.

### `Windows did not start the Visual C++ Redistributable installer`

The installer needs administrator rights, so Windows asks for permission. If the prompt was declined, or Windows does not allow the elevation, install again and allow the prompt. You can also install the build yourself, as above.

### `The Visual C++ Redistributable installer exited with code`

The installer ran and failed with that exit code. Install the build yourself from the link in the message, then install PHP again.

### `is not signed by Microsoft, so it was not run`

The downloaded file is not signed by Microsoft, so the plugin did not run it. A proxy or security software that rewrites HTTPS responses can cause this. Install the build yourself from the link in the message. If the message comes back, check the proxy.

### `php.exe does not start`

The runtime is recorded, or was just installed, but `php.exe` still does not start. Restart Windows and install PHP again. If it still fails, repair the Redistributable from Apps & Features (the x64 or x86 entry), then install PHP again.

### `The Composer installer does not match the sha384 that Composer publishes`

The installer that the plugin downloaded is not the one Composer publishes, so the install stopped before Composer was installed. Run the install again. If it fails every time, something between you and getcomposer.org is changing the file, such as a proxy that rewrites HTTPS responses. This message is only about the download: when `php.exe` cannot start, the install reports that instead, as above.

### `The code execution cannot proceed because VCRUNTIME140.dll was not found`

Windows shows this when you start `php.exe` yourself and the Visual C++ Redistributable is missing for that PHP. Install the x64 build from [Microsoft](https://aka.ms/vs/17/release/vc_redist.x64.exe), or `vc_redist.x86.exe` for x86 PHP, and run PHP again. The plugin installs the Redistributable during `vfox install`.

### `Failed to install composer.`

The plugin could not run Composer's installer with `php.exe`. Check that PHP runs on its own (`php -v`), and that getcomposer.org is reachable. Then install again.

## Linking an install that is already on the machine

### `vfox link --detect` finds no PHP

The plugin looks in the usual places, which [installs already on the machine](link.md) lists. A PHP in a folder that the system shares with other software is skipped on purpose: a distribution's PHP under `/usr/bin`, for example, would link the whole system. Link such an install by hand, with `vfox link php@<version> <folder that holds bin>`.

## Other

### Something else went wrong during an install

Run the install with `vfox --debug install php@<version>`. vfox then prints what it asks the plugin and what the plugin answers. Include the output when you report a problem: see [the issue tracker](https://github.com/version-fox/vfox-php/issues).
