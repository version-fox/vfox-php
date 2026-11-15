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

package common

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
)

func specsOf(combos []Combo) []string {
	specs := make([]string, 0, len(combos))
	for _, c := range combos {
		specs = append(specs, c.Spec)
	}
	return specs
}

func TestMatrix(t *testing.T) {
	t.Setenv(EnvPHPVersion, "")
	combos, err := Matrix()
	if err != nil {
		t.Fatal(err)
	}
	if got := specsOf(combos); !slices.Equal(got, DefaultPHPVersions) {
		t.Fatalf("default matrix = %v, want %v", got, DefaultPHPVersions)
	}

	t.Setenv(EnvPHPVersion, "8.4 latest 8.4 8.4.2")
	combos, err = Matrix()
	if err != nil {
		t.Fatal(err)
	}
	if got, want := specsOf(combos), []string{"8.4", "latest", "8.4.2"}; !slices.Equal(got, want) {
		t.Fatalf("matrix = %v, want %v: repeats dropped, order kept", got, want)
	}

	for _, bad := range []string{"php", "8.4;rm", "8..4", "8.4.1.2", "$(id)", "8.4-zts", "latest-zts"} {
		t.Setenv(EnvPHPVersion, bad)
		if _, err := Matrix(); err == nil {
			t.Errorf("PHP_VERSION=%q: no error", bad)
		}
	}
}

func TestSlug(t *testing.T) {
	for spec, want := range map[string]string{"latest": "php-latest", "8.3": "php-8_3", "8.3.12": "php-8_3_12", "8.3.12-zts": "php-8_3_12-zts"} {
		if got := (Combo{Spec: spec}).Slug(); got != want {
			t.Errorf("Slug(%q) = %q, want %q", spec, got, want)
		}
	}
}

func TestVersionPattern(t *testing.T) {
	cases := []struct {
		spec, version string
		match         bool
	}{
		{"latest", "8.5.0", true},
		{"latest", "8.5", false},
		{"8.3", "8.3.12", true},
		{"8.3", "8.30.1", false},
		{"8.3", "8.4.1", false},
		{"8", "8.1.2", true},
		{"8", "81.1.2", false},
		{"8.3.12", "8.3.12", true},
		{"8.3.12", "8.3.120", false},
	}
	for _, c := range cases {
		pattern, err := VersionPattern(c.spec)
		if err != nil {
			t.Fatalf("VersionPattern(%q): %v", c.spec, err)
		}
		if got := pattern.MatchString(c.version); got != c.match {
			t.Errorf("VersionPattern(%q) matches %q = %v, want %v", c.spec, c.version, got, c.match)
		}
	}
	if _, err := VersionPattern("8.3;rm"); err == nil {
		t.Error("VersionPattern accepted a spec with a shell character")
	}
}

// TestZTSCombo checks the -zts spec: it is a full release with the thread-safe
// suffix, its install is named with the suffix, and PHP_VERSION shows the release.
func TestZTSCombo(t *testing.T) {
	t.Setenv(EnvPHPVersion, "8.3.12-zts")
	combos, err := Matrix()
	if err != nil {
		t.Fatal(err)
	}
	if got := specsOf(combos); !slices.Equal(got, []string{"8.3.12-zts"}) {
		t.Fatalf("matrix = %v, want [8.3.12-zts]", got)
	}

	zts := Combo{Spec: "8.3.12-zts"}
	if !zts.ZTS() || (Combo{Spec: "8.3.12"}).ZTS() {
		t.Fatal("ZTS reports the wrong build")
	}
	if got := zts.InstalledName("8.3.12"); got != "8.3.12-zts" {
		t.Errorf("InstalledName = %q, want 8.3.12-zts", got)
	}
	if got := (Combo{Spec: "8.3.12"}).InstalledName("8.3.12"); got != "8.3.12" {
		t.Errorf("InstalledName = %q, want 8.3.12", got)
	}

	pattern, err := VersionPattern("8.3.12-zts")
	if err != nil {
		t.Fatal(err)
	}
	if !pattern.MatchString("8.3.12") || pattern.MatchString("8.3.120") {
		t.Errorf("VersionPattern(8.3.12-zts) = %v, want the release 8.3.12", pattern)
	}
	if _, err := VersionPattern("8.3-zts"); err == nil {
		t.Error("VersionPattern accepts 8.3-zts, which is not a release")
	}
}

func TestStripANSI(t *testing.T) {
	coloured := "Using latest version: \x1b[92m8.5.12\x1b[0m\n"
	if got, want := StripANSI(coloured), "Using latest version: 8.5.12\n"; got != want {
		t.Fatalf("StripANSI = %q, want %q", got, want)
	}
	if got := StripANSI("plain 8.5.12"); got != "plain 8.5.12" {
		t.Fatalf("StripANSI changed plain text: %q", got)
	}
}

func TestListsVersion(t *testing.T) {
	if !ListsVersion("php@8.5.0 (installed)", "8.5.0") {
		t.Error("php@8.5.0 not matched")
	}
	if !ListsVersion("Available versions:\n - 8.4.1\n - 8.5.0\n", "8.5.0") {
		t.Error("list entry 8.5.0 not matched")
	}
	if ListsVersion("8.5.0RC1", "8.5.0") {
		t.Error("8.5.0RC1 matched 8.5.0")
	}
	if ListsVersion("8.5.01", "8.5.0") {
		t.Error("8.5.01 matched 8.5.0")
	}
}

// vfox colours the version it prints, as `vfox use` does, and a colour code
// must not hide the version from the match.
func TestListsVersionIgnoresColour(t *testing.T) {
	coloured := "\x1b[92m8.5.12\x1b[0m (installed)\n"
	if !ListsVersion(coloured, "8.5.12") {
		t.Error("coloured 8.5.12 not matched")
	}
	if ListsVersion("\x1b[92m8.5.120\x1b[0m\n", "8.5.12") {
		t.Error("coloured 8.5.120 matched 8.5.12")
	}
}

func TestMissingModules(t *testing.T) {
	listing := "[PHP Modules]\r\nCore\r\nopenssl\r\ncurl\r\nmbstring\r\n\r\n[Zend Modules]\r\n"
	if got, want := MissingModules(listing, "openssl", "curl", "intl", "zip"), []string{"intl", "zip"}; !slices.Equal(got, want) {
		t.Fatalf("MissingModules = %v, want %v", got, want)
	}
}

func TestMissingModulesIgnoresColourAndCase(t *testing.T) {
	listing := "\x1b[1m[PHP Modules]\x1b[0m\nOpenSSL\ncurl\n"
	if got := MissingModules(listing, "openssl", "curl"); len(got) != 0 {
		t.Fatalf("MissingModules = %v, want none", got)
	}
}

func TestMaxJobs(t *testing.T) {
	t.Setenv(EnvMaxJobs, "")
	if n, err := MaxJobs(); err != nil || n != DefaultMaxJobs {
		t.Fatalf("default MaxJobs = %d, %v", n, err)
	}
	t.Setenv(EnvMaxJobs, "3")
	if n, err := MaxJobs(); err != nil || n != 3 {
		t.Fatalf("MaxJobs = %d, %v; want 3", n, err)
	}
	for _, bad := range []string{"0", "-1", "many"} {
		t.Setenv(EnvMaxJobs, bad)
		if _, err := MaxJobs(); err == nil {
			t.Errorf("E2E_MAX_JOBS=%q: no error", bad)
		}
	}
}

func TestRetryAttempts(t *testing.T) {
	t.Setenv(EnvRetryAttempts, "")
	if n, err := RetryAttempts(); err != nil || n != DefaultRetryAttempts {
		t.Fatalf("default RetryAttempts = %d, %v", n, err)
	}
	t.Setenv(EnvRetryAttempts, "0")
	if _, err := RetryAttempts(); err == nil {
		t.Error("E2E_RETRY_ATTEMPTS=0: no error")
	}
}

func TestContainerEnv(t *testing.T) {
	t.Setenv("MAKEFLAGS", "")
	if got := ContainerEnv()["MAKEFLAGS"]; got != DefaultMakeFlags {
		t.Errorf("MAKEFLAGS default = %q, want %q", got, DefaultMakeFlags)
	}
	t.Setenv("MAKEFLAGS", "-j8")
	if got := ContainerEnv()["MAKEFLAGS"]; got != "-j8" {
		t.Errorf("MAKEFLAGS from host = %q, want -j8", got)
	}
}

func TestContainerName(t *testing.T) {
	name := ContainerName(Combo{Spec: "8.3"}.Slug())
	if !strings.HasPrefix(name, "vfox-php-e2e-php-8_3-") {
		t.Errorf("ContainerName = %q, want the vfox-php-e2e-php-8_3- prefix", name)
	}
}

func TestRetry(t *testing.T) {
	ctx := context.Background()

	calls := 0
	err := Retry(ctx, 3, 0, func() error {
		calls++
		if calls < 2 {
			return errors.New("flaky")
		}
		return nil
	})
	if err != nil || calls != 2 {
		t.Fatalf("Retry after one failure: err=%v calls=%d, want nil and 2", err, calls)
	}

	calls = 0
	err = Retry(ctx, 3, 0, func() error {
		calls++
		return errors.New("down")
	})
	if err == nil || calls != 3 {
		t.Fatalf("Retry on constant failure: err=%v calls=%d, want an error and 3", err, calls)
	}

	stopped, cancel := context.WithCancel(ctx)
	cancel()
	calls = 0
	err = Retry(stopped, 3, time.Hour, func() error {
		calls++
		return errors.New("down")
	})
	if err == nil || calls != 1 {
		t.Fatalf("Retry on a done context: err=%v calls=%d, want an error after one call", err, calls)
	}
}

func TestRepoRoot(t *testing.T) {
	root, err := RepoRoot()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, "metadata.lua")); err != nil {
		t.Fatalf("RepoRoot %s has no metadata.lua: %v", root, err)
	}
}
