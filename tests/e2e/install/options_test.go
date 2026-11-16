// Copyright 2026 Han Li and contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package install

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// darwinFormulae are the Homebrew formulae that bin/install asks about on a Mac,
// each installed at /fake/<name>. gmp and libsodium are installed only when asked.
func darwinFormulae(gmp, sodium bool) map[string]string {
	formulae := map[string]string{}
	for _, name := range []string{
		"bison", "bzip2", "freetype", "gettext", "icu4c", "jpeg", "krb5", "libedit",
		"libiconv", "libpng", "libxml2", "libxslt", "libzip", "openssl@3", "readline", "webp", "zlib",
	} {
		formulae[name] = "/fake/" + name
	}
	if gmp {
		formulae["gmp"] = "/fake/gmp"
	}
	if sodium {
		formulae["libsodium"] = "/fake/libsodium"
	}
	return formulae
}

// TestDarwinDiagnosticsStayOutOfTheArguments checks that a missing optional library
// is reported on stderr, and never becomes a configure argument.
func TestDarwinDiagnosticsStayOutOfTheArguments(t *testing.T) {
	for _, tc := range []struct {
		name        string
		gmp, sodium bool
	}{
		{"both-installed", true, true},
		{"gmp-only", true, false},
		{"sodium-only", false, true},
		{"neither", false, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := newSession(t, darwinHost(darwinFormulae(tc.gmp, tc.sodium)))
			r := s.run("PHP_VERSION=8.4.10\nconstruct_configure_options /fake/php")
			requireStatus(t, r, 0)
			if strings.Contains(r.stdout, "not found") {
				t.Errorf("dependency diagnostics leaked into the arguments:\n%s", r.stdout)
			}
			if !hasLine(r.stdout, "--prefix=/fake/php") {
				t.Errorf("the arguments lack --prefix=/fake/php:\n%s", r.stdout)
			}
			requireOptional(t, r, tc.gmp, "gmp", "--with-gmp=/fake/gmp")
			requireOptional(t, r, tc.sodium, "sodium", "--with-sodium=/fake/libsodium")
		})
	}
}

// requireOptional checks that an optional library is an argument when it is
// installed, and that when it is not, the absence is reported on stderr.
func requireOptional(t *testing.T, r result, installed bool, name, argument string) {
	t.Helper()
	if installed {
		if !hasLine(r.stdout, argument) {
			t.Errorf("want %s in the arguments:\n%s", argument, r.stdout)
		}
		return
	}
	for _, line := range strings.Split(r.stdout, "\n") {
		if strings.HasPrefix(line, "--with-"+name+"=") {
			t.Errorf("%s is not installed, yet its argument is there: %s", name, line)
		}
	}
	if !strings.Contains(r.stderr, name+" not found") {
		t.Errorf("no message on stderr for the missing %s:\n%s", name, r.stderr)
	}
}

// TestOpenSSLFollowsThePHPVersion checks that PHP 8.1 and later build against
// OpenSSL 3, and that older PHP builds against OpenSSL 1.1.
func TestOpenSSLFollowsThePHPVersion(t *testing.T) {
	formulae := map[string]string{"openssl@3": "/fake/openssl@3", "openssl@1.1": "/fake/openssl@1.1"}
	for _, tc := range []struct {
		versions []string
		want     string
	}{
		{[]string{"8.1.0", "8.4.2", "8.5.0"}, "/fake/openssl@3"},
		{[]string{"7.4.33", "8.0.30"}, "/fake/openssl@1.1"},
	} {
		for _, version := range tc.versions {
			t.Run(version, func(t *testing.T) {
				s := newSession(t, darwinHost(formulae))
				r := s.run(fmt.Sprintf("PHP_VERSION=%s\nhomebrew_openssl_path", version))
				requireStatus(t, r, 0)
				if got := strings.TrimSpace(r.stdout); got != tc.want {
					t.Errorf("OpenSSL for PHP %s is %q, want %q", version, got, tc.want)
				}
			})
		}
	}
}

// TestOpenSSLIsNeverSilentlyReplaced checks that an old PHP does not fall back to
// OpenSSL 3, and that a missing OpenSSL formula is an error, not an empty path.
func TestOpenSSLIsNeverSilentlyReplaced(t *testing.T) {
	for _, tc := range []struct {
		name     string
		version  string
		formulae map[string]string
	}{
		{"old-php-without-openssl-1.1", "7.4.33", map[string]string{"openssl@3": "/fake/openssl@3"}},
		{"new-php-without-openssl-3", "8.4.2", map[string]string{"openssl@1.1": "/fake/openssl@1.1"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := newSession(t, darwinHost(tc.formulae))
			r := s.run(fmt.Sprintf("PHP_VERSION=%s\nhomebrew_openssl_path", tc.version))
			if r.status == 0 {
				t.Errorf("exit status 0: a missing OpenSSL must fail:\n%s", r.stdout)
			}
			if r.stdout != "" {
				t.Errorf("a path was printed for a missing OpenSSL: %q", r.stdout)
			}
			if !strings.Contains(r.stderr, "ERROR:") {
				t.Errorf("no error on stderr:\n%s", r.stderr)
			}
		})
	}
}

// TestExplicitConfigureOptionsReplaceThePlatformOptions checks that
// PHP_CONFIGURE_OPTIONS replaces the platform options, so an OpenSSL the user names
// works without a Homebrew formula, and gmp is not added on its own.
func TestExplicitConfigureOptionsReplaceThePlatformOptions(t *testing.T) {
	s := newSession(t, linuxWith("libgmp.so.10 => /lib/libgmp.so.10", "gmp.h")).
		with("PHP_CONFIGURE_OPTIONS=--with-openssl=/custom/openssl")
	r := s.run("construct_configure_options /tmp/php-test")
	requireStatus(t, r, 0)
	if !hasLine(r.stdout, "--with-openssl=/custom/openssl") {
		t.Errorf("the explicit OpenSSL is missing:\n%s", r.stdout)
	}
	if hasLine(r.stdout, "--with-gmp") {
		t.Errorf("the platform options were added beside the explicit ones:\n%s", r.stdout)
	}
}

// TestPCREJITFollowsPHPWithoutPCREJIT checks that PCRE JIT stays on, as PHP has it,
// unless PHP_WITHOUT_PCRE_JIT is set to something other than no.
func TestPCREJITFollowsPHPWithoutPCREJIT(t *testing.T) {
	for _, tc := range []struct {
		name       string
		env        []string
		withoutJIT bool
	}{
		{"unset", nil, false},
		{"no", []string{"PHP_WITHOUT_PCRE_JIT=no"}, false},
		{"yes", []string{"PHP_WITHOUT_PCRE_JIT=yes"}, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := newSession(t, linuxHost()).with(tc.env...)
			r := s.run("construct_configure_options /fake/php")
			requireStatus(t, r, 0)
			if got := hasLine(r.stdout, "--without-pcre-jit"); got != tc.withoutJIT {
				t.Errorf("--without-pcre-jit present = %t, want %t:\n%s", got, tc.withoutJIT, r.stdout)
			}
		})
	}
}

// TestZTSFollowsThePHPVersion checks the configure option of a thread-safe build:
// PHP 8.0 and later take --enable-zts, PHP 5.x and 7.x take --enable-maintainer-zts,
// and an NTS build takes neither.
func TestZTSFollowsThePHPVersion(t *testing.T) {
	for _, tc := range []struct {
		name, script, want string
	}{
		{"8.4", "PHP_ZTS=yes\nPHP_VERSION=8.4.5", "--enable-zts"},
		{"8.0", "PHP_ZTS=yes\nPHP_VERSION=8.0.30", "--enable-zts"},
		{"7.4", "PHP_ZTS=yes\nPHP_VERSION=7.4.33", "--enable-maintainer-zts"},
		{"5.6", "PHP_ZTS=yes\nPHP_VERSION=5.6.40", "--enable-maintainer-zts"},
		{"nts", "PHP_ZTS=no\nPHP_VERSION=8.4.5", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := newSession(t, linuxHost())
			r := s.run(tc.script + "\nconstruct_configure_options /fake/php")
			requireStatus(t, r, 0)
			for _, flag := range []string{"--enable-zts", "--enable-maintainer-zts"} {
				if got, want := hasLine(r.stdout, flag), flag == tc.want; got != want {
					t.Errorf("%s in the arguments = %t, want %t:\n%s", flag, got, want, r.stdout)
				}
			}
		})
	}
}

// TestGmpAndSodiumNeedTheirLibraryAndHeader checks that gmp and sodium are enabled
// when the library and its header are there, and that without the header they are
// left out, with a message.
func TestGmpAndSodiumNeedTheirLibraryAndHeader(t *testing.T) {
	libraries := "libgmp.so.10 (libc6,x86-64) => /lib/libgmp.so.10\n" +
		"libsodium.so.23 (libc6,x86-64) => /lib/libsodium.so.23"

	t.Run("with-headers", func(t *testing.T) {
		s := newSession(t, linuxWith(libraries, "gmp.h", "sodium.h"))
		r := s.run("construct_configure_options /fake/php")
		requireStatus(t, r, 0)
		for _, arg := range []string{"--with-gmp", "--with-sodium"} {
			if !hasLine(r.stdout, arg) {
				t.Errorf("want %s in the arguments:\n%s", arg, r.stdout)
			}
		}
	})

	t.Run("without-headers", func(t *testing.T) {
		s := newSession(t, linuxWith(libraries))
		r := s.run("construct_configure_options /fake/php")
		requireStatus(t, r, 0)
		for _, arg := range []string{"--with-gmp", "--with-sodium"} {
			if hasLine(r.stdout, arg) {
				t.Errorf("%s is in the arguments without its header:\n%s", arg, r.stdout)
			}
		}
		for _, message := range []string{"gmp not found", "sodium not found"} {
			if !strings.Contains(r.stderr, message) {
				t.Errorf("no %q on stderr:\n%s", message, r.stderr)
			}
		}
	})
}

// TestJPEGAndPNGComeFromTheSystemLibgd checks that bin/install passes no per-library
// JPEG or PNG options: the build uses --with-external-gd, and gd finds them in the
// system libgd.
func TestJPEGAndPNGComeFromTheSystemLibgd(t *testing.T) {
	s := newSession(t, linuxWith(
		"libjpeg.so.8 => /lib/libjpeg.so.8\nlibpng16.so.16 => /lib/libpng16.so.16",
		"jpeglib.h", "png.h",
	))
	r := s.run("construct_configure_options /fake/php")
	requireStatus(t, r, 0)
	for _, line := range strings.Split(r.stdout, "\n") {
		if strings.HasPrefix(line, "--with-jpeg") || strings.HasPrefix(line, "--with-png") {
			t.Errorf("a per-library option is passed: %s", line)
		}
	}
	if !hasLine(r.stdout, "--with-external-gd") {
		t.Errorf("--with-external-gd is missing:\n%s", r.stdout)
	}
}

// sampleVersions are one release of each PHP line that bin/install builds, from 5.3,
// the oldest that the plugin offers, to 8.5.
var sampleVersions = []string{
	"5.3.29", "5.4.45", "5.6.40", "7.0.33", "7.1.33", "7.2.34", "7.3.33", "7.4.33",
	"8.0.30", "8.4.27", "8.5.12",
}

// versionedOption is a configure option that only some PHP versions take, with the
// sample versions that take it. configure ignores an option that a version does not
// take, and most versions warn about it, so bin/install passes it to those versions.
type versionedOption struct {
	flag   string
	takers []string
}

// linuxVersionedOptions lists the Linux options, as the configure script of each
// release accepts them.
var linuxVersionedOptions = []versionedOption{
	{"--enable-mbregex", []string{"5.4.45", "5.6.40", "7.0.33", "7.1.33", "7.2.34", "7.3.33", "7.4.33", "8.0.30", "8.4.27", "8.5.12"}},
	{"--enable-wddx", []string{"5.3.29", "5.4.45", "5.6.40", "7.0.33", "7.1.33", "7.2.34", "7.3.33"}},
	{"--enable-zip", []string{"5.3.29", "5.4.45", "5.6.40", "7.0.33", "7.1.33", "7.2.34", "7.3.33"}},
	{"--with-gd", []string{"5.3.29", "5.4.45", "5.6.40", "7.0.33", "7.1.33", "7.2.34", "7.3.33"}},
	{"--enable-gd", []string{"7.4.33", "8.0.30", "8.4.27", "8.5.12"}},
	{"--with-external-gd", []string{"7.4.33", "8.0.30", "8.4.27", "8.5.12"}},
	{"--with-zip", []string{"7.4.33", "8.0.30", "8.4.27", "8.5.12"}},
	{"--with-xmlrpc", []string{"5.3.29", "5.4.45", "5.6.40", "7.0.33", "7.1.33", "7.2.34", "7.3.33", "7.4.33"}},
	{"--enable-gd-native-ttf", []string{"5.3.29", "5.4.45", "5.6.40", "7.0.33", "7.1.33"}},
	{"--with-mysql=mysqlnd", []string{"5.3.29", "5.4.45", "5.6.40"}},
}

// darwinVersionedOptions lists the Homebrew options, which take a prefix as a value.
var darwinVersionedOptions = []versionedOption{
	{"--with-freetype-dir", []string{"5.3.29", "5.4.45", "5.6.40", "7.0.33", "7.1.33", "7.2.34", "7.3.33"}},
	{"--with-icu-dir", []string{"5.3.29", "5.4.45", "5.6.40", "7.0.33", "7.1.33", "7.2.34", "7.3.33"}},
	{"--with-jpeg-dir", []string{"5.3.29", "5.4.45", "5.6.40", "7.0.33", "7.1.33", "7.2.34", "7.3.33"}},
	{"--with-png-dir", []string{"5.3.29", "5.4.45", "5.6.40", "7.0.33", "7.1.33", "7.2.34", "7.3.33"}},
	{"--with-libxml-dir", []string{"5.3.29", "5.4.45", "5.6.40", "7.0.33", "7.1.33", "7.2.34", "7.3.33"}},
	{"--with-webp-dir", []string{"7.0.33", "7.1.33", "7.2.34", "7.3.33"}},
	{"--with-libzip", []string{"5.6.40", "7.0.33", "7.1.33", "7.2.34", "7.3.33"}},
	{"--with-zlib-dir", []string{"5.3.29", "5.4.45", "5.6.40", "7.0.33", "7.1.33", "7.2.34", "7.3.33", "7.4.33", "8.0.30"}},
	{"--with-sodium", []string{"7.2.34", "7.3.33", "7.4.33", "8.0.30", "8.4.27", "8.5.12"}},
}

// takenBy reports whether the version is one of the takers.
func takenBy(version string, takers []string) bool {
	for _, taker := range takers {
		if taker == version {
			return true
		}
	}
	return false
}

// TestVersionedOptionsFollowThePHPVersion checks that each Linux option that only some
// PHP versions take is passed to those versions and to no others. PEAR and mhash are
// passed to every version: PHP warns that they are deprecated, but they still build.
func TestVersionedOptionsFollowThePHPVersion(t *testing.T) {
	for _, version := range sampleVersions {
		t.Run(version, func(t *testing.T) {
			s := newSession(t, linuxHost()).with("PHP_VERSION=" + version)
			r := s.run("construct_configure_options /fake/php")
			requireStatus(t, r, 0)
			for _, opt := range linuxVersionedOptions {
				want := takenBy(version, opt.takers)
				if got := hasLine(r.stdout, opt.flag); got != want {
					t.Errorf("%s in the arguments = %t, want %t:\n%s", opt.flag, got, want, r.stdout)
				}
			}
			for _, flag := range []string{"--with-mhash", "--with-pear"} {
				if !hasLine(r.stdout, flag) {
					t.Errorf("%s is missing from the arguments:\n%s", flag, r.stdout)
				}
			}
		})
	}
}

// TestDarwinVersionedOptionsFollowThePHPVersion checks that each Homebrew option is
// passed with its prefix to the PHP versions that take it, and to no others.
func TestDarwinVersionedOptionsFollowThePHPVersion(t *testing.T) {
	formulae := darwinFormulae(true, true)
	formulae["openssl@1.1"] = "/fake/openssl@1.1"
	for _, version := range sampleVersions {
		t.Run(version, func(t *testing.T) {
			s := newSession(t, darwinHost(formulae)).with("PHP_VERSION=" + version)
			r := s.run("construct_configure_options /fake/php")
			requireStatus(t, r, 0)
			for _, opt := range darwinVersionedOptions {
				want := takenBy(version, opt.takers)
				if got := hasLinePrefix(r.stdout, opt.flag+"="); got != want {
					t.Errorf("%s in the arguments = %t, want %t:\n%s", opt.flag, got, want, r.stdout)
				}
			}
		})
	}
}

// TestSodiumNeedsPHP72 checks that sodium is passed to PHP 7.2 and later only. The
// sodium extension came with PHP 7.2, so an older configure does not take the option,
// and bin/install does not report sodium as missing for a PHP without it.
func TestSodiumNeedsPHP72(t *testing.T) {
	libraries := "libsodium.so.23 (libc6,x86-64) => /lib/libsodium.so.23"
	for _, tc := range []struct {
		version string
		want    bool
	}{
		{"7.1.33", false},
		{"7.2.34", true},
	} {
		t.Run(tc.version, func(t *testing.T) {
			s := newSession(t, linuxWith(libraries, "sodium.h")).with("PHP_VERSION=" + tc.version)
			r := s.run("construct_configure_options /fake/php")
			requireStatus(t, r, 0)
			if got := hasLine(r.stdout, "--with-sodium"); got != tc.want {
				t.Errorf("--with-sodium in the arguments = %t, want %t:\n%s", got, tc.want, r.stdout)
			}
			if !tc.want && strings.Contains(r.stderr, "sodium") {
				t.Errorf("a message about sodium for PHP %s:\n%s", tc.version, r.stderr)
			}
		})
	}
}

// TestPCREJITOffNeedsPHP70 checks that PHP 5.x, which has no --without-pcre-jit, is not
// given it even when PHP_WITHOUT_PCRE_JIT asks for it.
func TestPCREJITOffNeedsPHP70(t *testing.T) {
	for _, tc := range []struct {
		version string
		want    bool
	}{
		{"5.6.40", false},
		{"7.0.33", true},
	} {
		t.Run(tc.version, func(t *testing.T) {
			s := newSession(t, linuxHost()).with("PHP_WITHOUT_PCRE_JIT=yes", "PHP_VERSION="+tc.version)
			r := s.run("construct_configure_options /fake/php")
			requireStatus(t, r, 0)
			if got := hasLine(r.stdout, "--without-pcre-jit"); got != tc.want {
				t.Errorf("--without-pcre-jit in the arguments = %t, want %t:\n%s", got, tc.want, r.stdout)
			}
		})
	}
}

// TestLocateIsNotUsed checks that bin/install finds the libraries with ldconfig and
// the compiler, and never with locate.
func TestLocateIsNotUsed(t *testing.T) {
	s := newSession(t, linuxWith("libgmp.so.10 => /lib/libgmp.so.10", "gmp.h"))
	requireStatus(t, s.run("construct_configure_options /fake/php"), 0)
	if log, err := os.ReadFile(filepath.Join(s.work, "locate.log")); err == nil {
		t.Errorf("bin/install called locate: %s", log)
	}
}
