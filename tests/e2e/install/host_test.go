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
	"os/exec"
	"runtime"
	"strings"
	"testing"
)

// homebrewArguments pairs the Homebrew formulae that bin/install asks about on a
// Mac with the configure argument that carries the prefix of each.
var homebrewArguments = []struct{ formula, flag string }{
	{"bzip2", "--with-bz2"},
	{"freetype", "--with-freetype-dir"},
	{"gettext", "--with-gettext"},
	{"icu4c", "--with-icu-dir"},
	{"jpeg", "--with-jpeg-dir"},
	{"libedit", "--with-libedit"},
	{"libiconv", "--with-iconv"},
	{"libpng", "--with-png-dir"},
	{"libxml2", "--with-libxml-dir"},
	{"libxslt", "--with-xsl"},
	{"libzip", "--with-libzip"},
	{"openssl@3", "--with-openssl"},
	{"readline", "--with-readline"},
	{"webp", "--with-webp-dir"},
	{"zlib", "--with-zlib-dir"},
	{"gmp", "--with-gmp"},
	{"libsodium", "--with-sodium"},
}

// TestHomebrewOfThisMac checks that the configure arguments carry the Homebrew
// prefixes of the Mac the test runs on: a formula that Homebrew reports installed
// has its argument with its prefix, and a formula that is not installed has none.
// Nothing is faked here: bin/install runs with the real uname and the real brew.
// It runs only on macOS with brew installed.
func TestHomebrewOfThisMac(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("reads the Homebrew of a Mac")
	}
	brew, err := exec.LookPath("brew")
	if err != nil {
		t.Skip("brew is not installed")
	}
	s := newHostSession(t)
	r := s.run("PHP_VERSION=8.5.12\nconstruct_configure_options /tmp/php-host")
	requireStatus(t, r, 0)
	if !hasLine(r.stdout, "--prefix=/tmp/php-host") {
		t.Errorf("the arguments lack the prefix:\n%s", r.stdout)
	}

	for _, want := range homebrewArguments {
		prefix := brewPrefix(t, brew, want.formula)
		if prefix == "" {
			if hasLinePrefix(r.stdout, want.flag+"=") {
				t.Errorf("%s is not installed, yet its argument is there:\n%s", want.formula, r.stdout)
			}
			continue
		}
		if !hasLine(r.stdout, want.flag+"="+prefix) {
			t.Errorf("want %s=%s for %s in the arguments:\n%s", want.flag, prefix, want.formula, r.stdout)
		}
	}
}

// brewPrefix returns the prefix of an installed formula, or "" when Homebrew does
// not have the formula, which is how bin/install asks as well.
func brewPrefix(t *testing.T, brew, formula string) string {
	t.Helper()
	installed, err := exec.Command(brew, "ls", "--versions", formula).Output()
	if err != nil || strings.TrimSpace(string(installed)) == "" {
		return ""
	}
	prefix, err := exec.Command(brew, "--prefix", formula).Output()
	if err != nil {
		t.Fatalf("brew --prefix %s: %v", formula, err)
	}
	return strings.TrimSpace(string(prefix))
}

// hasLinePrefix reports whether one of the lines of text starts with prefix.
func hasLinePrefix(text, prefix string) bool {
	for _, line := range strings.Split(text, "\n") {
		if strings.HasPrefix(line, prefix) {
			return true
		}
	}
	return false
}
