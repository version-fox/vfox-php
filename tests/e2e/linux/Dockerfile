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

# The Linux E2E image (see docs/e2e.md): a clean Ubuntu with the packages a PHP
# source build needs, vfox from its release, and this checkout as the plugin.
# tests/e2e/linux starts one container per PHP version from it and drives each
# one through exec calls. testcontainers-go builds it, and it cannot use
# BuildKit, so the steps are chained with && rather than heredocs.

FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

ARG VFOX_VERSION=1.1.0
ARG VFOX_SHA256_X86_64=3b33c3c468b27bc17aecf0d6d3af24fe49fe204972984904a136a47b402a0ee4
ARG VFOX_SHA256_AARCH64=e702e057dfe588200727dfb3cf786d181b13f015cbcc9e13679a3edcfd07e430

# The packages the CI workflows install for a PHP source build. The build
# configures mysqlnd rather than libmysqlclient, so that library is not needed.
RUN apt-get update \
    && apt-get install --assume-yes --no-install-recommends \
        autoconf bison build-essential ca-certificates curl gettext git \
        libcurl4-openssl-dev libedit-dev libgd-dev libicu-dev libjpeg-dev libonig-dev \
        libpng-dev libpq-dev libreadline-dev libsqlite3-dev libssl-dev libxml2-dev \
        libxslt-dev libzip-dev openssl pkg-config re2c zip zlib1g-dev \
    && rm --recursive --force /var/lib/apt/lists/*

# vfox from its release, checked against the sha256 of the release's checksums.txt.
RUN case "$(uname --machine)" in \
        x86_64) vfox_arch=x86_64; vfox_sha256="${VFOX_SHA256_X86_64}" ;; \
        aarch64) vfox_arch=aarch64; vfox_sha256="${VFOX_SHA256_AARCH64}" ;; \
        *) echo "unsupported architecture $(uname --machine)" >&2; exit 1 ;; \
    esac \
    && vfox_dir="vfox_${VFOX_VERSION}_linux_${vfox_arch}" \
    && curl --fail --silent --show-error --location --output /tmp/vfox.tar.gz \
        "https://github.com/version-fox/vfox/releases/download/v${VFOX_VERSION}/${vfox_dir}.tar.gz" \
    && echo "${vfox_sha256}  /tmp/vfox.tar.gz" | sha256sum --check \
    && tar --extract --gzip --file /tmp/vfox.tar.gz --directory /usr/local/bin --strip-components=1 "${vfox_dir}/vfox" \
    && rm --force /tmp/vfox.tar.gz \
    && vfox --version

# The checkout as the plugin archive that `vfox add -s` installs, as CI makes it.
WORKDIR /plugin
COPY . /plugin
RUN zip --quiet --recurse-paths /opt/php-plugin.zip .

CMD ["sleep", "infinity"]
