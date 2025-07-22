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

## Prerequirements

PHP installation requires some dependencies. Please install the dependencies based on the error messages, or refer to [.github/workflows/test-\*.yaml](https://github.com/version-fox/vfox-php/tree/main/.github/workflows) for guidance.

### macOS

To install PHP on macOS, you'll need a set of packages installed via homebrew.

```shell
brew install autoconf automake bison freetype gd gettext icu4c krb5 libedit libiconv libjpeg libpng libxml2 libzip pkg-config re2c zlib
```

There's also a set of optional packages which enable additional extensions to be enabled:

```shell
brew install gmp libsodium imagemagick
```

Note that the supported extensions are not exhaustive, so you may need to edit the [bin/install](./bin/install) script to support additional extension. Feel free to submit a PR for any missing extensions.
