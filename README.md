# vfox-php

[PHP](https://www.php.net/) plugin for [vfox](https://vfox.dev/).

## Usage

```shell
# install plugin
vfox add php

# install an available version
vfox search php
# or specific version
vfox install php@8.4.5

# or nts version
vfox install php@8.4.5-nts
```

The version list combines current and archived Windows binaries, sorted newest
first. Plain Windows versions select thread-safe (TS) builds; `-nts` selects NTS.
Linux and macOS source versions come directly from PHP's official JSON API.
Network failures report the upstream URL instead of returning an empty list.

## Prerequirements

PHP installation requires some dependencies. Please install the dependencies based on the error messages, or refer to [.github/workflows/test-\*.yaml](https://github.com/version-fox/vfox-php/tree/main/.github/workflows) for guidance.

### macOS

To install PHP on macOS, you'll need a set of packages installed via homebrew.

```shell
brew install autoconf automake bison freetype gd gettext icu4c krb5 libedit libiconv libjpeg libpng libxml2 libzip openssl@3 pkg-config re2c zlib
```

PHP 8.1 and newer use `openssl@3` on macOS. Older PHP versions require a
compatible older OpenSSL installation; the build reports a missing dependency
instead of silently selecting OpenSSL 3 or omitting HTTPS support. Homebrew no
longer supplies `openssl@1.1` through its normal supported formulae. See the
[PHP OpenSSL compatibility requirements](https://www.php.net/manual/en/openssl.requirements.php).
If you supply `PHP_CONFIGURE_OPTIONS`, you remain responsible for configuring
the dependency paths; automatic macOS dependency selection is bypassed.

There's also a set of optional packages which enable additional extensions to be enabled:

```shell
brew install gmp libsodium imagemagick
```

Note that the supported extensions are not exhaustive, so you may need to edit the [bin/install](./bin/install) script to support additional extension. Feel free to submit a PR for any missing extensions.

## Releasing this plugin

Maintainers can publish from **Actions → Plugin → Run workflow** on the default
branch by entering a stable plugin version without the `v` prefix. The shared
workflow updates `metadata.lua`, creates the version commit and tag, and publishes
the ZIP and manifest in this repository. No local tag or extra release token is
needed. Pull requests run checks only; PR titles no longer trigger publication.

Existing version-tag pushes are supported when `PLUGIN.version` already matches
the tag. If publication fails, re-run the original failed job to resume it.

The workflow follows the shared `@v1` release-tool version. Updating the tool does
not release this plugin. See the [shared workflow documentation](https://github.com/version-fox/plugin-manifest-action)
for the package contract and first-rollout requirements.
