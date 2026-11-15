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
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// requirement is one line of linux_build_requirements: a tool, a set of pkg-config
// modules or a header that bin/install checks on Linux, what needs it, and the
// Debian or Ubuntu package that provides it.
type requirement struct {
	kind, name, need, apt string
}

// linuxRequirements reads the requirements from bin/install, so that the tests check
// the list that the script has and not a copy of it. The session's
// PHP_CONFIGURE_OPTIONS decides whether the platform requirements are in it.
func linuxRequirements(t *testing.T, s *session) []requirement {
	t.Helper()
	r := s.run("linux_build_requirements")
	requireStatus(t, r, 0)
	var reqs []requirement
	for _, line := range strings.Split(strings.TrimSpace(r.stdout), "\n") {
		fields := strings.Split(line, "|")
		if len(fields) != 4 {
			t.Fatalf("a requirement has %d fields, want 4: %q", len(fields), line)
		}
		reqs = append(reqs, requirement{fields[0], fields[1], fields[2], fields[3]})
	}
	return reqs
}

// has reports whether the host has the requirement.
func (h host) has(req requirement) bool {
	switch req.kind {
	case "tool":
		return slices.Contains(h.tools, req.name)
	case "pkg":
		for _, module := range strings.Fields(req.name) {
			if !slices.Contains(h.pkgs, module) {
				return false
			}
		}
		return true
	default:
		return slices.Contains(h.headers, req.name)
	}
}

// without returns the host with the requirement missing. The lists of the host are
// copied, so the shared lists of linuxHost are not changed.
func (h host) without(req requirement) host {
	switch req.kind {
	case "tool":
		h.tools = slices.DeleteFunc(slices.Clone(h.tools), func(s string) bool { return s == req.name })
	case "pkg":
		for _, module := range strings.Fields(req.name) {
			h.pkgs = slices.DeleteFunc(slices.Clone(h.pkgs), func(s string) bool { return s == module })
		}
	default:
		h.headers = slices.DeleteFunc(slices.Clone(h.headers), func(s string) bool { return s == req.name })
	}
	return h
}

// aptPackages returns the packages that the install hint on stderr names.
func aptPackages(stderr string) []string {
	for _, line := range strings.Split(stderr, "\n") {
		if rest, ok := strings.CutPrefix(line, "  sudo apt-get install --assume-yes"); ok {
			return strings.Fields(rest)
		}
	}
	return nil
}

// TestLinuxHostHasEveryRequirement checks that the host the other tests use has each
// tool, pkg-config module and header that bin/install asks for on Linux. Without it,
// the healthy installs in the other tests would fail.
func TestLinuxHostHasEveryRequirement(t *testing.T) {
	for _, req := range linuxRequirements(t, newSession(t, linuxHost())) {
		if !linuxHost().has(req) {
			t.Errorf("linuxHost lacks the %s %s, which bin/install checks", req.kind, req.name)
		}
	}
}

// TestMissingBuildDependencyStopsTheInstall checks each requirement in turn. When
// one is missing, install_php fails before it moves the source or compiles anything,
// and stderr names the requirement and the package that provides it.
func TestMissingBuildDependencyStopsTheInstall(t *testing.T) {
	names := strings.NewReplacer("/", "_", ".", "_")
	for _, req := range linuxRequirements(t, newSession(t, linuxHost())) {
		t.Run(req.kind+"_"+names.Replace(req.name), func(t *testing.T) {
			s := newSession(t, linuxHost().without(req))
			source := filepath.Join(s.work, "plain", "php")
			fakeSource(t, source)

			r := s.run("install_php " + shellQuote(source))
			if r.status == 0 {
				t.Fatalf("install_php succeeded without %s:\n%s", req.name, r.stdout)
			}
			if !strings.Contains(r.stderr, "ERROR: PHP cannot be built") || !strings.Contains(r.stderr, "Nothing was compiled") {
				t.Errorf("no error that says nothing was compiled:\n%s", r.stderr)
			}
			if want := "  - " + req.name + ": " + req.need; !hasLine(r.stderr, want) {
				t.Errorf("want the line %q on stderr:\n%s", want, r.stderr)
			}
			if !slices.Contains(aptPackages(r.stderr), req.apt) {
				t.Errorf("the install hint lacks %s: %v", req.apt, aptPackages(r.stderr))
			}
			for _, log := range []string{"configure.log", "make.log"} {
				if _, err := os.Stat(filepath.Join(s.work, log)); !os.IsNotExist(err) {
					t.Errorf("%s exists, so the build ran", log)
				}
			}
			if _, err := os.Stat(source); err != nil {
				t.Errorf("the source was moved: %v", err)
			}
			requireGone(t, source+"_source")
		})
	}
}

// TestEveryMissingDependencyIsListedOnce checks that a host without any of them is
// told about all of them in one run, and that the install hint names each package
// once: cc and make are both in build-essential.
func TestEveryMissingDependencyIsListedOnce(t *testing.T) {
	s := newSession(t, host{uname: linuxHost().uname})
	reqs := linuxRequirements(t, s)
	source := filepath.Join(s.work, "plain", "php")
	fakeSource(t, source)

	r := s.run("install_php " + shellQuote(source))
	if r.status == 0 {
		t.Fatalf("install_php succeeded on a host without any dependency:\n%s", r.stdout)
	}
	for _, req := range reqs {
		if want := "  - " + req.name + ": " + req.need; !hasLine(r.stderr, want) {
			t.Errorf("want the line %q on stderr:\n%s", want, r.stderr)
		}
	}
	seen := map[string]bool{}
	for _, pkg := range aptPackages(r.stderr) {
		if seen[pkg] {
			t.Errorf("%s is named twice in the install hint: %v", pkg, aptPackages(r.stderr))
		}
		seen[pkg] = true
	}
	if !seen["build-essential"] {
		t.Errorf("the install hint lacks build-essential: %v", aptPackages(r.stderr))
	}
}

// TestExplicitConfigureOptionsSkipThePlatformRequirements checks that the four
// requirements of the platform options are asked for only when PHP_CONFIGURE_OPTIONS
// is not set, as those options are only used then.
func TestExplicitConfigureOptionsSkipThePlatformRequirements(t *testing.T) {
	platform := []requirement{
		{kind: "header", name: "openssl/ssl.h"},
		{kind: "header", name: "readline/readline.h"},
		{kind: "header", name: "libintl.h"},
		{kind: "pkg", name: "libxslt"},
	}
	missing := linuxHost()
	for _, req := range platform {
		missing = missing.without(req)
	}

	t.Run("default-options", func(t *testing.T) {
		s := newSession(t, missing)
		source := filepath.Join(s.work, "plain", "php")
		fakeSource(t, source)
		r := s.run("install_php " + shellQuote(source))
		if r.status == 0 {
			t.Fatalf("install_php succeeded without the platform requirements:\n%s", r.stdout)
		}
		for _, req := range platform {
			if !strings.Contains(r.stderr, "  - "+req.name+": ") {
				t.Errorf("%s is not named on stderr:\n%s", req.name, r.stderr)
			}
		}
	})

	t.Run("explicit-options", func(t *testing.T) {
		s := newSession(t, missing).with("PHP_CONFIGURE_OPTIONS=--with-openssl=/custom/openssl")
		source := filepath.Join(s.work, "plain", "php")
		fakeSource(t, source)
		requireStatus(t, s.run("install_php "+shellQuote(source)), 0)
	})
}

// TestMacOSIsNotChecked checks that the Linux check does not run on a Mac. The Mac
// has its own checks, of Homebrew and of OpenSSL, and a Mac with those builds PHP.
func TestMacOSIsNotChecked(t *testing.T) {
	// The Darwin branch extends PKG_CONFIG_PATH, which the tests' shell (set -u)
	// rejects when it is unset. bin/install itself runs without set -u.
	s := newSession(t, darwinHost(darwinFormulae(false, false))).with("PKG_CONFIG_PATH=")
	source := filepath.Join(s.work, "mac", "php")
	fakeSource(t, source)

	r := s.run("PHP_VERSION=8.5.12\ninstall_php " + shellQuote(source))
	requireStatus(t, r, 0)
	if strings.Contains(r.stderr, "build dependencies are missing") {
		t.Errorf("the Linux check ran on a Mac:\n%s", r.stderr)
	}
}
