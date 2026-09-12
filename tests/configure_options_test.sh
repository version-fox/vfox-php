#!/usr/bin/env bash
set -euo pipefail
source bin/install

# Optional dependency diagnostics must not become ./configure arguments.
uname() { echo Darwin; }
exit_if_homebrew_not_installed() { :; }
homebrew_package_path() {
  case "$1" in
    gmp) [[ "$with_gmp" == yes ]] && echo /fake/gmp ;;
    libsodium) [[ "$with_sodium" == yes ]] && echo /fake/libsodium ;;
    *) echo "/fake/$1" ;;
  esac
  return 0
}
PHP_VERSION=8.4.10
PHP_CONFIGURE_OPTIONS=
diagnostics=$(mktemp)
trap 'rm -f "$diagnostics"' EXIT
for with_gmp in yes no; do
  for with_sodium in yes no; do
    options=$(construct_configure_options /fake/php 2>"$diagnostics")
    [[ "$options" != *'not found'* ]] || {
      echo 'Dependency diagnostics leaked into configure arguments' >&2
      exit 1
    }
    [[ "$options" == *'--prefix=/fake/php'* ]]
    if [[ "$with_gmp" == yes ]]; then
      [[ "$options" == *'--with-gmp=/fake/gmp'* ]]
    else
      [[ "$options" != *'--with-gmp='* ]]
      grep -q 'gmp not found' "$diagnostics"
    fi
    if [[ "$with_sodium" == yes ]]; then
      [[ "$options" == *'--with-sodium=/fake/libsodium'* ]]
    else
      [[ "$options" != *'--with-sodium='* ]]
      grep -q 'sodium not found' "$diagnostics"
    fi
  done
done
echo 'Optional dependency diagnostics and configure arguments passed'
