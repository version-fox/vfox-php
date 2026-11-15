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
	"regexp"
	"strings"
	"testing"
)

// buildDirOf returns the build directory that bin/install picks for an install path.
func buildDirOf(t *testing.T, s *session, installPath string) string {
	t.Helper()
	r := s.run("build_dir_for " + shellQuote(installPath))
	requireStatus(t, r, 0)
	return strings.TrimSpace(r.stdout)
}

// spacedInstallPath is an install path with a space in it, as a VFOX_HOME with a
// space gives one.
func spacedInstallPath(s *session) string {
	return filepath.Join(s.work, "vfox home", "cache", "php", "v-8.5.12")
}

// requireGone fails the test when one of the paths is still there, as a link or
// as anything else.
func requireGone(t *testing.T, paths ...string) {
	t.Helper()
	for _, path := range paths {
		if _, err := os.Lstat(path); !os.IsNotExist(err) {
			t.Errorf("%s is still there (%v)", path, err)
		}
	}
}

// TestBuildBaseIsOutsideAnySpace checks where PHP is built: the first of the XDG
// data directory, the data directory under HOME, and /var/tmp that holds no space.
func TestBuildBaseIsOutsideAnySpace(t *testing.T) {
	for _, tc := range []struct {
		name string
		env  func(s *session) []string
		want func(s *session) string
	}{
		{
			name: "home",
			want: func(s *session) string {
				return filepath.Join(s.work, "home", ".local", "share", "vfox-php")
			},
		},
		{
			name: "xdg",
			env: func(s *session) []string {
				return []string{"XDG_DATA_HOME=" + filepath.Join(s.work, "xdg")}
			},
			want: func(s *session) string {
				return filepath.Join(s.work, "xdg", "vfox-php")
			},
		},
		{
			name: "xdg-with-space",
			env: func(s *session) []string {
				return []string{"XDG_DATA_HOME=" + filepath.Join(s.work, "xdg data")}
			},
			want: func(s *session) string {
				return filepath.Join(s.work, "home", ".local", "share", "vfox-php")
			},
		},
		{
			name: "home-with-space",
			env: func(s *session) []string {
				return []string{"HOME=" + filepath.Join(s.work, "home dir")}
			},
			want: func(s *session) string {
				return fmt.Sprintf("/var/tmp/vfox-php-%d", os.Getuid())
			},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := newSession(t, linuxHost())
			if tc.env != nil {
				s = s.with(tc.env(s)...)
			}
			r := s.run("build_base")
			requireStatus(t, r, 0)
			if got, want := strings.TrimSpace(r.stdout), tc.want(s); got != want {
				t.Errorf("build base is %q, want %q", got, want)
			}
		})
	}
}

// TestBuildDirIsNamedByItsPath checks that the build directory of an install path is
// under the build base, has no space, and is not shared with another install path.
func TestBuildDirIsNamedByItsPath(t *testing.T) {
	s := newSession(t, linuxHost())
	dir := buildDirOf(t, s, spacedInstallPath(s))
	base := filepath.Join(s.work, "home", ".local", "share", "vfox-php", "builds") + string(os.PathSeparator)
	if !strings.HasPrefix(dir, base) || !regexp.MustCompile(`^[0-9]+$`).MatchString(strings.TrimPrefix(dir, base)) {
		t.Errorf("build directory %q is not a checksum under %s", dir, base)
	}
	if strings.ContainsAny(dir, " \t") {
		t.Errorf("build directory %q holds a space", dir)
	}
	if other := buildDirOf(t, s, spacedInstallPath(s)+"-two"); other == dir {
		t.Errorf("two install paths share the build directory %s", dir)
	}
}

// TestSpacedInstallPathLinksToABuildOutsideIt checks that an install path with a
// space becomes a link to a build directory without spaces: PHP is configured with
// that directory as its prefix and installed there, and php.ini goes into the link.
func TestSpacedInstallPathLinksToABuildOutsideIt(t *testing.T) {
	s := newSession(t, linuxHost())
	spaced := spacedInstallPath(s)
	fakeSource(t, spaced)
	buildDir := buildDirOf(t, s, spaced)

	// The subshell ends the EXIT trap that install_php sets: bin/install does that
	// once the Composer step is done too.
	r := s.run("(install_php " + shellQuote(spaced) + "; trap - EXIT)")
	requireStatus(t, r, 0)

	target, err := os.Readlink(spaced)
	if err != nil {
		t.Fatalf("the install path is not a link: %v", err)
	}
	if target != buildDir {
		t.Errorf("the link points to %q, want %q", target, buildDir)
	}
	args := s.readArguments()
	if !hasLine(args, "--prefix="+buildDir) {
		t.Errorf("configure was not given the prefix %s:\n%s", buildDir, args)
	}
	for _, arg := range strings.Split(strings.TrimSpace(args), "\n") {
		if strings.Contains(arg, " ") {
			t.Errorf("a configure argument holds a space: %q", arg)
		}
	}
	if !hasLine(readLog(t, s, "make.log"), "make install") {
		t.Errorf("make install did not run")
	}
	if _, err := os.Stat(filepath.Join(spaced, "conf.d", "php.ini")); err != nil {
		t.Errorf("php.ini is not in the link's conf.d: %v", err)
	}
	requireGone(t, buildDir+".source")
}

// TestFailedBuildLeavesNothingBehind checks that when configure fails, the link,
// the build directory and the source are all removed.
func TestFailedBuildLeavesNothingBehind(t *testing.T) {
	s := newSession(t, linuxHost())
	failed := filepath.Join(s.work, "vfox home", "cache", "php", "v-failed")
	fakeSource(t, failed)
	buildDir := buildDirOf(t, s, failed)

	r := s.with("FAKE_CONFIGURE_FAIL=1").run("install_php " + shellQuote(failed))
	if r.status == 0 {
		t.Fatalf("a failed configure must fail the install:\n%s", r.stdout)
	}
	if !hasLine(readLog(t, s, "configure.log"), "configure") {
		t.Errorf("configure was not run, so the failure is not its own")
	}
	requireGone(t, failed, buildDir, buildDir+".source")
}

// TestFailureAfterTheBuildRemovesIt checks that a failure after the build, such as
// the Composer step, removes the build too: vfox cannot reach the build directory.
func TestFailureAfterTheBuildRemovesIt(t *testing.T) {
	s := newSession(t, linuxHost())
	later := filepath.Join(s.work, "vfox home", "cache", "php", "v-later")
	fakeSource(t, later)
	buildDir := buildDirOf(t, s, later)

	r := s.run("(install_php " + shellQuote(later) + "; false)")
	if r.status == 0 {
		t.Fatalf("the failure after the build was not reported")
	}
	if !hasLine(readLog(t, s, "make.log"), "make install") {
		t.Errorf("the build did not finish before the failure")
	}
	requireGone(t, later, buildDir)
}

// TestPlainInstallPathIsBuiltInPlace checks that an install path without a space is
// the prefix itself, with no link.
func TestPlainInstallPathIsBuiltInPlace(t *testing.T) {
	s := newSession(t, linuxHost())
	plain := filepath.Join(s.work, "plain", "php")
	fakeSource(t, plain)
	requireStatus(t, s.run("(install_php "+shellQuote(plain)+")"), 0)

	info, err := os.Lstat(plain)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode()&os.ModeSymlink != 0 {
		t.Errorf("the install path without a space is a link")
	}
	if !hasLine(s.readArguments(), "--prefix="+plain) {
		t.Errorf("configure was not given the prefix %s", plain)
	}
	if _, err := os.Stat(filepath.Join(plain, "conf.d", "php.ini")); err != nil {
		t.Errorf("php.ini is missing: %v", err)
	}
}

// TestRemoveBuildRemovesOnlyTheBuildOfALink checks the uninstall step: it removes
// the build directory that a link points to, and leaves the link, which vfox
// removes itself, and every other directory alone.
func TestRemoveBuildRemovesOnlyTheBuildOfALink(t *testing.T) {
	s := newSession(t, linuxHost())
	spaced := spacedInstallPath(s)
	fakeSource(t, spaced)
	buildDir := buildDirOf(t, s, spaced)
	requireStatus(t, s.run("(install_php "+shellQuote(spaced)+"; trap - EXIT)"), 0)

	plain := filepath.Join(s.work, "plain", "php")
	fakeSource(t, plain)
	requireStatus(t, s.run("(install_php "+shellQuote(plain)+")"), 0)

	requireStatus(t, s.run("remove_build "+shellQuote(spaced)), 0)
	requireGone(t, buildDir)
	if _, err := os.Lstat(spaced); err != nil {
		t.Errorf("the link was removed by remove_build: %v", err)
	}

	requireStatus(t, s.run("remove_build "+shellQuote(plain)), 0)
	if _, err := os.Stat(plain); err != nil {
		t.Errorf("an install path without a space was removed: %v", err)
	}
}

// TestRemoveBuildRefusesAnotherDirectory checks that a link to a directory which is
// not a build directory is not followed, and that the directory is left alone.
func TestRemoveBuildRefusesAnotherDirectory(t *testing.T) {
	s := newSession(t, linuxHost())
	outside := filepath.Join(s.work, "elsewhere dir")
	mkdir(t, outside)
	link := filepath.Join(s.work, "outside link")
	if err := os.Symlink(outside, link); err != nil {
		t.Fatal(err)
	}

	r := s.run("remove_build " + shellQuote(link))
	if r.status == 0 {
		t.Errorf("remove_build accepted a link to %s", outside)
	}
	if !strings.Contains(r.stderr, "not a vfox-php build directory") {
		t.Errorf("no refusal on stderr:\n%s", r.stderr)
	}
	if _, err := os.Stat(outside); err != nil {
		t.Errorf("the directory the link points to was removed: %v", err)
	}
}

// TestUninstallEntryPointRemovesTheBuild runs bin/install as the PreUninstall hook
// does: bin/install --remove-build <install path>.
func TestUninstallEntryPointRemovesTheBuild(t *testing.T) {
	s := newSession(t, linuxHost())
	spaced := spacedInstallPath(s)
	fakeSource(t, spaced)
	buildDir := buildDirOf(t, s, spaced)
	requireStatus(t, s.run("(install_php "+shellQuote(spaced)+"; trap - EXIT)"), 0)

	requireStatus(t, s.exec("--remove-build", spaced), 0)
	requireGone(t, buildDir)
	if _, err := os.Lstat(spaced); err != nil {
		t.Errorf("the link was removed by bin/install: %v", err)
	}
}

// readLog returns a log of the session, which the fake commands write.
func readLog(t *testing.T, s *session, name string) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(s.work, name))
	if err != nil {
		t.Fatalf("read the log %s: %v", name, err)
	}
	return string(data)
}
