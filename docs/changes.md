# Changes

[中文](zh-CN/changes.md) | [English](changes.md)

What each release changed. The releases before 0.3.0 are on the [GitHub releases page](https://github.com/version-fox/vfox-php/releases).

## Unreleased

- Development: a dev container, Go E2E suites for Linux and Windows that install PHP with vfox inside containers, lint, format and license-header checks in CI, and documentation in English and Chinese.
- The Lua and shell sources carry the Apache-2.0 license header. No behaviour changes.

## 0.3.2

- Optional dependency diagnostics, such as `gmp not found`, are printed to stderr and no longer end up in the configure arguments.

## 0.3.1

- Restored PHP release discovery and platform installation.
- Releases are published by the shared plugin workflow.
- CI initialises vfox before it selects PHP, and it verifies the managed PHP.
- CI no longer keeps an empty legacy config file.

## 0.3.0

- Linux supports the LTS releases.
- Downloads use the redirected URLs.
- Without Homebrew, Linux builds include gmp and sodium when they are found.
- The README was updated.
