# Copyright 2026 Han Li and contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The repository dev container (see docs/e2e.md): the pinned Go toolchain, the
# Lua, license and workflow tools the local checks use, vfox, the Docker CLI
# that drives the host daemon for the E2E suites, and the packages a PHP source
# build needs. The versions below are the ones the lint, license and E2E
# workflows pin, and the ones tests/e2e/linux/Dockerfile and
# tests/e2e/windows/Dockerfile use for vfox; change them together.
#
# The image is multi-arch (linux/amd64 and linux/arm64); the downloads below
# select their asset per architecture.

FROM golang:1.27.1

# Docker CLI (client only): drives the host daemon from the shell, the same
# daemon the E2E suites drive through the Docker Go API.
COPY --from=docker:29-cli /usr/local/bin/docker /usr/local/bin/docker

ARG STYLUA_VERSION=2.5.2
ARG LUA_LANGUAGE_SERVER_VERSION=3.19.1
ARG VFOX_VERSION=1.1.0
ARG VFOX_SHA256_X86_64=3b33c3c468b27bc17aecf0d6d3af24fe49fe204972984904a136a47b402a0ee4
ARG VFOX_SHA256_AARCH64=e702e057dfe588200727dfb3cf786d181b13f015cbcc9e13679a3edcfd07e430
ARG LICENSE_EYE_VERSION=0.9.0
ARG ADDLICENSE_VERSION=1.2.0
ARG ACTIONLINT_VERSION=1.7.12

# Heredocs need BuildKit, which the dev container tooling uses by default. The
# E2E image builds stay on the chained-`&&` form: testcontainers-go cannot use
# BuildKit (see tests/e2e/linux/Dockerfile).

RUN <<EOF
set -o errexit -o nounset -o xtrace
apt-get update
apt-get install --assume-yes --no-install-recommends \
    autoconf \
    bison \
    build-essential \
    ca-certificates \
    curl \
    gettext \
    git \
    libcurl4-openssl-dev \
    libedit-dev \
    libgd-dev \
    libicu-dev \
    libjpeg-dev \
    libonig-dev \
    libpng-dev \
    libpq-dev \
    libreadline-dev \
    libsqlite3-dev \
    libssl-dev \
    libxml2-dev \
    libxslt-dev \
    libzip-dev \
    openssl \
    pkg-config \
    re2c \
    unzip \
    zip \
    zlib1g-dev
rm --recursive --force /var/lib/apt/lists/*
case "$(dpkg --print-architecture)" in
    amd64)
        stylua_asset=stylua-linux-x86_64.zip
        luals_asset="lua-language-server-${LUA_LANGUAGE_SERVER_VERSION}-linux-x64.tar.gz"
        vfox_dir="vfox_${VFOX_VERSION}_linux_x86_64"
        vfox_sha256="${VFOX_SHA256_X86_64}"
        ;;
    arm64)
        stylua_asset=stylua-linux-aarch64.zip
        luals_asset="lua-language-server-${LUA_LANGUAGE_SERVER_VERSION}-linux-arm64.tar.gz"
        vfox_dir="vfox_${VFOX_VERSION}_linux_aarch64"
        vfox_sha256="${VFOX_SHA256_AARCH64}"
        ;;
    *)
        echo "FAIL unsupported architecture $(dpkg --print-architecture)" >&2
        exit 1
        ;;
esac
curl --fail --silent --show-error --location --output /tmp/stylua.zip \
    "https://github.com/JohnnyMorganz/StyLua/releases/download/v${STYLUA_VERSION}/${stylua_asset}"
unzip -q /tmp/stylua.zip -d /usr/local/bin
rm --force /tmp/stylua.zip
curl --fail --silent --show-error --location --output /tmp/luals.tar.gz \
    "https://github.com/LuaLS/lua-language-server/releases/download/${LUA_LANGUAGE_SERVER_VERSION}/${luals_asset}"
mkdir --parents /opt/lua-language-server
tar --extract --gzip --file /tmp/luals.tar.gz --directory /opt/lua-language-server
rm --force /tmp/luals.tar.gz
ln --symbolic /opt/lua-language-server/bin/lua-language-server /usr/local/bin/lua-language-server
curl --fail --silent --show-error --location --output /tmp/vfox.tar.gz \
    "https://github.com/version-fox/vfox/releases/download/v${VFOX_VERSION}/${vfox_dir}.tar.gz"
echo "${vfox_sha256}  /tmp/vfox.tar.gz" | sha256sum --check
tar --extract --gzip --file /tmp/vfox.tar.gz --directory /usr/local/bin --strip-components=1 "${vfox_dir}/vfox"
rm --force /tmp/vfox.tar.gz
stylua --version
lua-language-server --version
vfox --version
EOF

RUN <<EOF
set -o errexit -o nounset -o xtrace
GOBIN=/usr/local/bin go install github.com/apache/skywalking-eyes/cmd/license-eye@v${LICENSE_EYE_VERSION}
GOBIN=/usr/local/bin go install github.com/google/addlicense@v${ADDLICENSE_VERSION}
GOBIN=/usr/local/bin go install github.com/rhysd/actionlint/cmd/actionlint@v${ACTIONLINT_VERSION}
command -v license-eye addlicense actionlint
EOF
