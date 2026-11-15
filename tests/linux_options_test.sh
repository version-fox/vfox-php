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

# The Linux configure options, and the build directory of an install path that
# holds a space, of bin/install. The system is faked: uname, ldconfig, the
# compiler's header check and locate are replaced, and PHP's own build is
# replaced by small scripts, so this runs on any host.
set -euo pipefail
source bin/install

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export TEST_WORK="$work"
export HOME="$work/home"
unset XDG_DATA_HOME
mkdir -p "$HOME"

uname() { echo "Linux test 6.8.0 x86_64 GNU/Linux"; }
exit_if_homebrew_not_installed() { :; }
locate() { echo "locate was called: $*" >>"$work/locate.log"; }
# ldconfig -p lists the libraries in the cache: FAKE_LIBRARIES holds those lines.
ldconfig() { printf '%s\n' "${FAKE_LIBRARIES:-}"; }
# The header check pipes "#include <header>" to the compiler; FAKE_HEADERS lists
# the headers that the fake system has.
cc() {
  local header
  header=$(sed -n 's/^#include <\(.*\)>$/\1/p')
  [[ ",${FAKE_HEADERS:-}," == *",$header,"* ]]
}
# make records what it is asked to do. make install creates the prefix that
# configure was given, as the real make install does.
make() {
  echo "make $*" >>"$TEST_WORK/make.log"
  if [ "${1:-}" = "install" ]; then
    mkdir -p "$(sed -n 's/^--prefix=//p' "$TEST_WORK/configure.args")"
  fi
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

expect_equal() {
  if [ "$1" != "$2" ]; then
    echo "got [$1], want [$2]" >&2
    exit 1
  fi
}

# A PHP source tree with a fake buildconf and configure. The configure script
# records its arguments, one per line, for the checks.
fake_source() {
  local dir=$1
  mkdir -p "$dir"
  cat >"$dir/buildconf" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat >"$dir/configure" <<'EOF'
#!/usr/bin/env bash
if [ -n "${FAKE_CONFIGURE_FAIL:-}" ]; then
  exit 1
fi
printf '%s\n' "$@" >"$TEST_WORK/configure.args"
EOF
  chmod +x "$dir/buildconf" "$dir/configure"
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
options=$(construct_configure_options /fake/php 2>"$work/diagnostics")
refuse_option --with-gmp
refuse_option --with-sodium
grep -q 'gmp not found' "$work/diagnostics"
grep -q 'sodium not found' "$work/diagnostics"
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
if [ -s "$work/locate.log" ]; then
  echo "bin/install called locate: $(cat "$work/locate.log")" >&2
  exit 1
fi
echo "locate is not used"

# PHP_CONFIGURE_OPTIONS replaces the platform options, as documented.
FAKE_LIBRARIES=$'libgmp.so.10 => /lib/libgmp.so.10'
FAKE_HEADERS="gmp.h"
PHP_CONFIGURE_OPTIONS="--with-openssl=/custom/openssl"
options=$(construct_configure_options /fake/php)
expect_option --with-openssl=/custom/openssl
refuse_option --with-gmp
PHP_CONFIGURE_OPTIONS=
echo "PHP_CONFIGURE_OPTIONS replaces the platform options"

# The build directory is outside any path with a space, whichever base is used.
HOME="$work/home"
unset XDG_DATA_HOME
expect_equal "$(build_base)" "$work/home/.local/share/vfox-php"
XDG_DATA_HOME="$work/xdg"
expect_equal "$(build_base)" "$work/xdg/vfox-php"
XDG_DATA_HOME="$work/xdg data"
expect_equal "$(build_base)" "$work/home/.local/share/vfox-php"
unset XDG_DATA_HOME
HOME="$work/home dir"
expect_equal "$(build_base)" "/var/tmp/vfox-php-$(id -u)"
HOME="$work/home"
build_dir=$(build_dir_for "$work/vfox home/cache/php/v-8.5.12")
case "$build_dir" in
  "$work/home/.local/share/vfox-php/builds/"[0-9]*) ;;
  *)
    echo "unexpected build directory: $build_dir" >&2
    exit 1
    ;;
esac
if [[ "$build_dir" =~ [[:space:]] ]]; then
  echo "the build directory holds a space: $build_dir" >&2
  exit 1
fi
echo "the build directory holds no space"

# An install path with a space becomes a link to its build directory. PHP is
# configured with that directory as its prefix, installed there, and the
# php.ini goes into the link's conf.d.
spaced="$work/vfox home/cache/php/v-8.5.12"
fake_source "$spaced"
build_dir=$(build_dir_for "$spaced")
# As bin/install does once the Composer step is done too: the cleanup is removed.
(install_php "$spaced"; trap - EXIT)
[ -L "$spaced" ]
expect_equal "$(readlink "$spaced")" "$build_dir"
grep -qx -- "--prefix=$build_dir" "$work/configure.args"
if grep -q ' ' "$work/configure.args"; then
  echo "a configure argument holds a space" >&2
  exit 1
fi
grep -qx -- "install" <(sed 's/^make //' "$work/make.log")
[ -f "$spaced/conf.d/php.ini" ]
[ ! -e "$build_dir.source" ]
echo "an install path with a space links to a build directory without spaces"

# A failed build leaves nothing behind: no link, no build directory, no source.
failed="$work/vfox home/cache/php/v-failed"
fake_source "$failed"
failed_build=$(build_dir_for "$failed")
# The subshell is not part of an && or || list, so set -e stops install_php at
# the failed configure, as it does when bin/install runs it.
set +e
(
  set -e
  export FAKE_CONFIGURE_FAIL=1
  install_php "$failed"
)
failed_status=$?
set -e
[ "$failed_status" -ne 0 ]
[ ! -L "$failed" ]
[ ! -e "$failed" ]
[ ! -e "$failed_build" ]
[ ! -e "$failed_build.source" ]
echo "a failed build leaves no link and no build directory"

# A failure after the build, such as the Composer step, removes the build too,
# because vfox cannot reach the build directory to remove it.
later="$work/vfox home/cache/php/v-later"
fake_source "$later"
later_build=$(build_dir_for "$later")
set +e
(
  set -e
  install_php "$later"
  false
)
later_status=$?
set -e
[ "$later_status" -ne 0 ]
[ ! -L "$later" ]
[ ! -e "$later_build" ]
echo "a failure after the build removes it too"

# An install path without a space is built as before: the prefix is the path.
plain="$work/plain/php"
fake_source "$plain"
(install_php "$plain")
[ ! -L "$plain" ]
grep -qx -- "--prefix=$plain" "$work/configure.args"
[ -f "$plain/conf.d/php.ini" ]
echo "an install path without a space is built in place"

# The uninstall step removes the build directory a link points to, and only
# that. vfox removes the link itself.
remove_build "$spaced"
[ ! -e "$build_dir" ]
[ -L "$spaced" ]
remove_build "$plain"
[ -d "$plain" ]
echo "remove_build removes the build directory of a link and nothing else"

# A link to a directory that is not a build directory is not followed.
outside="$work/elsewhere dir"
mkdir -p "$outside"
ln -s "$outside" "$work/outside link"
status=0
remove_build "$work/outside link" 2>/dev/null || status=$?
[ "$status" -ne 0 ]
[ -d "$outside" ]
echo "remove_build refuses a link to a directory that is not a build directory"

echo "Linux configure options and build directories passed"
