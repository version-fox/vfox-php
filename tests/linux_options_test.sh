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

# The Linux configure options of bin/install. The system is faked: uname,
# ldconfig, the compiler's header check and locate are replaced, so this runs on
# any host and checks what bin/install asks configure for.
set -euo pipefail
source bin/install

diagnostics=$(mktemp)
locate_log=$(mktemp)
trap 'rm -f "$diagnostics" "$locate_log"' EXIT

uname() { echo "Linux test 6.8.0 x86_64 GNU/Linux"; }
exit_if_homebrew_not_installed() { :; }
locate() { echo "locate was called: $*" >>"$locate_log"; }
# ldconfig -p lists the libraries in the cache: FAKE_LIBRARIES holds those lines.
ldconfig() { printf '%s\n' "${FAKE_LIBRARIES:-}"; }
# The header check pipes "#include <header>" to the compiler; FAKE_HEADERS lists
# the headers that the fake system has.
cc() {
  local header
  header=$(sed -n 's/^#include <\(.*\)>$/\1/p')
  [[ ",${FAKE_HEADERS:-}," == *",$header,"* ]]
}

PHP_CONFIGURE_OPTIONS=
unset PHP_WITHOUT_PCRE_JIT PHP_WITHOUT_PEAR FAKE_LIBRARIES FAKE_HEADERS

expect_option() {
  if ! grep -qx -- "$1" <<<"$options"; then
    echo "missing configure argument: $1" >&2
    exit 1
  fi
}

refuse_option() {
  if grep -qx -- "$1" <<<"$options"; then
    echo "unexpected configure argument: $1" >&2
    exit 1
  fi
}

# PCRE JIT is PHP's own default: no flag unless PHP_WITHOUT_PCRE_JIT asks for one.
options=$(construct_configure_options /fake/php)
refuse_option --without-pcre-jit
PHP_WITHOUT_PCRE_JIT=no
options=$(construct_configure_options /fake/php)
refuse_option --without-pcre-jit
PHP_WITHOUT_PCRE_JIT=yes
options=$(construct_configure_options /fake/php)
expect_option --without-pcre-jit
unset PHP_WITHOUT_PCRE_JIT
echo "PCRE JIT follows PHP_WITHOUT_PCRE_JIT"

# gmp and sodium are enabled when the library and its header are there.
FAKE_LIBRARIES=$'libgmp.so.10 (libc6,x86-64) => /lib/libgmp.so.10\nlibsodium.so.23 (libc6,x86-64) => /lib/libsodium.so.23'
FAKE_HEADERS="gmp.h,sodium.h"
options=$(construct_configure_options /fake/php)
expect_option --with-gmp
expect_option --with-sodium
echo "gmp and sodium are found with their headers"

# Without the headers, they are left out, and the build says why on stderr.
FAKE_HEADERS=""
options=$(construct_configure_options /fake/php 2>"$diagnostics")
refuse_option --with-gmp
refuse_option --with-sodium
grep -q 'gmp not found' "$diagnostics"
grep -q 'sodium not found' "$diagnostics"
echo "gmp and sodium are left out without their headers, with a message"

# JPEG and PNG come from the system libgd (--with-external-gd); no per-library
# options are passed, and the old -dir options that PHP does not know are gone.
FAKE_LIBRARIES=$'libjpeg.so.8 => /lib/libjpeg.so.8\nlibpng16.so.16 => /lib/libpng16.so.16'
FAKE_HEADERS="jpeglib.h,png.h"
options=$(construct_configure_options /fake/php)
if grep -q -- '--with-jpeg\|--with-png' <<<"$options"; then
  echo "unexpected JPEG or PNG option" >&2
  exit 1
fi
expect_option --with-external-gd
echo "JPEG and PNG are left to the system libgd"

# locate is not needed any more, so it is never called.
if [ -s "$locate_log" ]; then
  echo "bin/install called locate: $(cat "$locate_log")" >&2
  exit 1
fi
echo "locate is not used"

# The argument list keeps each argument whole, even one that holds a space.
# (install_php does not reach this for such a path; see below.)
spaced="/home/John Doe/.vfox/sdks/php-8.5.12"
options=$(construct_configure_options "$spaced")
expect_option "--prefix=$spaced"
expect_option "--sysconfdir=$spaced"
expect_option "--with-config-file-scan-dir=$spaced/conf.d"
echo "the argument list keeps arguments whole"

# PHP cannot install into a path with spaces: install_php refuses it before it
# moves, builds or creates anything.
refused="/tmp/vfox home-$$/php-8.5.12"
if install_php "$refused" 2>"$diagnostics"; then
  echo "install_php accepted an install path with spaces" >&2
  exit 1
fi
grep -q 'cannot be installed into a path with spaces' "$diagnostics"
[ ! -e "$refused" ]
echo "install_php refuses an install path with spaces before compiling"

# PHP_CONFIGURE_OPTIONS replaces the platform options, as documented.
FAKE_LIBRARIES=$'libgmp.so.10 => /lib/libgmp.so.10'
FAKE_HEADERS="gmp.h"
PHP_CONFIGURE_OPTIONS="--with-openssl=/custom/openssl"
options=$(construct_configure_options /fake/php)
expect_option --with-openssl=/custom/openssl
refuse_option --with-gmp
PHP_CONFIGURE_OPTIONS=
echo "PHP_CONFIGURE_OPTIONS replaces the platform options"

echo "Linux configure options passed"
