#!/usr/bin/env bash
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

set -euo pipefail
source bin/install

installed_three=yes
installed_one=yes
homebrew_package_path() {
  if [[ "$1" == openssl@3 && "$installed_three" == yes ]] || [[ "$1" == openssl@1.1 && "$installed_one" == yes ]]; then
    echo "/fake/$1"
  fi
}
for version in 8.1.0 8.4.2 8.5.0; do
  PHP_VERSION=$version
  [[ "$(homebrew_openssl_path)" == /fake/openssl@3 ]]
done
for version in 7.4.33 8.0.30; do
  PHP_VERSION=$version
  [[ "$(homebrew_openssl_path)" == /fake/openssl@1.1 ]]
done
PHP_VERSION=7.4.33
installed_one=no
if homebrew_openssl_path 2>/dev/null; then
  echo "Old PHP must not silently use OpenSSL 3" >&2; exit 1
fi
PHP_VERSION=8.4.2
installed_three=no
if homebrew_openssl_path 2>/dev/null; then
  echo "Missing OpenSSL must report a dependency error" >&2; exit 1
fi
echo "OpenSSL compatibility and missing dependency cases passed"

# Custom configure options must still work without a Homebrew OpenSSL formula.
PHP_CONFIGURE_OPTIONS=--with-openssl=/custom/openssl
options=$(construct_configure_options /tmp/php-test)
[[ "$options" == *--with-openssl=/custom/openssl* ]]
echo "Explicit configure options preserved"
