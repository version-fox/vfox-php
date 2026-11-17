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
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Environment knobs of the suites. Each has a default, so a bare
// `go test -run TestE2E ./linux` runs the whole matrix.
const (
	// EnvPHPVersion lists the PHP versions to install, separated by spaces.
	// Each is a vfox version: latest, a major.minor such as 8.3, or a full
	// release such as 8.3.12.
	EnvPHPVersion = "PHP_VERSION"
	// EnvMaxJobs bounds how many containers run at once.
	EnvMaxJobs = "E2E_MAX_JOBS"
	// EnvRetryAttempts bounds the attempts of a step that needs the network.
	EnvRetryAttempts = "E2E_RETRY_ATTEMPTS"

	// DefaultMaxJobs is 2: each Linux container compiles PHP, which takes most
	// of the CPUs of a runner.
	DefaultMaxJobs = 2
	// DefaultRetryAttempts is the attempts of a network-bound step by default.
	DefaultRetryAttempts = 3
	// DefaultMakeFlags is the build parallelism inside a Linux container unless
	// MAKEFLAGS is set on the host.
	DefaultMakeFlags = "-j2"
	// RetryBackoff is the pause after the first failed attempt. Each further
	// failure waits one more RetryBackoff.
	RetryBackoff = 10 * time.Second

	// ReadmeURL is the README the plugin's notes link to; `vfox info php` prints it.
	ReadmeURL = "https://github.com/version-fox/vfox-php/blob/main/README.md"
	// UnknownVersion is a version no release has. PreInstall must refuse it by name.
	UnknownVersion = "99.0.0"
	// UnknownVersionError is what vfox prints when PreInstall refuses UnknownVersion.
	UnknownVersionError = "PHP version not found: " + UnknownVersion
)

// DefaultPHPVersions is the matrix when PHP_VERSION is unset: the newest
// release, and the newest patch of 8.3.
var DefaultPHPVersions = []string{"latest", "8.3"}

// ZTSSpec is the thread-safe build of a full release, which the Linux suite
// installs on top of the matrix. Windows has no -zts build, so its suite does not.
const ZTSSpec = "8.3.12-zts"

// PassThroughEnvs are copied from the host into every Linux container when set.
var PassThroughEnvs = []string{"MAKEFLAGS", "PHP_WITH_PEAR", "PHP_WITH_MHASH"}

// LinuxModules are the modules a Linux build provides. The build turns each
// one on through its platform options or its global options.
var LinuxModules = []string{
	"openssl", "curl", "mbstring", "zip", "intl", "bcmath", "sockets", "mysqli",
	"pdo_mysql", "soap", "gd", "xsl", "readline", "calendar", "exif", "gmp", "sodium",
}

// WindowsModules are the modules every Windows install has: the php.ini that
// the plugin writes enables openssl.
var WindowsModules = []string{"openssl"}

// specPattern accepts latest, a major, a major.minor or a full release, and a full
// release with -zts, the thread-safe build of Linux and macOS.
var specPattern = regexp.MustCompile(`^(latest|[0-9]+(\.[0-9]+){0,2}|[0-9]+\.[0-9]+\.[0-9]+-zts)$`)

// ansiPattern matches the colour and cursor sequences vfox prints.
var ansiPattern = regexp.MustCompile(`\x1b\[[0-9;?]*[ -/]*[@-~]`)

// Combo is one PHP version, installed and checked by one container.
type Combo struct {
	// Spec is the version handed to vfox: latest, 8.3, 8.3.12 or 8.3.12-zts.
	Spec string
}

// Slug names the combo in test names and container names.
func (c Combo) Slug() string {
	return "php-" + strings.NewReplacer(".", "_").Replace(c.Spec)
}

// ZTS reports whether the combo is the thread-safe build of its release.
func (c Combo) ZTS() bool {
	return strings.HasSuffix(c.Spec, "-zts")
}

// InstalledName is the name vfox gives the install of a release: the release
// itself, or the release with -zts for the thread-safe build.
func (c Combo) InstalledName(release string) string {
	if c.ZTS() {
		return release + "-zts"
	}
	return release
}

// Matrix returns one combo per PHP version that PHP_VERSION selects, in the
// order given, without repeats. A value that is not latest, a major, a
// major.minor or a full release is an error.
func Matrix() ([]Combo, error) {
	specs := strings.Fields(os.Getenv(EnvPHPVersion))
	if len(specs) == 0 {
		specs = DefaultPHPVersions
	}
	seen := make(map[string]bool, len(specs))
	var combos []Combo
	for _, spec := range specs {
		if !specPattern.MatchString(spec) {
			return nil, fmt.Errorf("%s: %q is not latest, a major, a major.minor or a full release", EnvPHPVersion, spec)
		}
		if !seen[spec] {
			seen[spec] = true
			combos = append(combos, Combo{Spec: spec})
		}
	}
	return combos, nil
}

// MaxJobs returns how many containers may run at once: E2E_MAX_JOBS, or
// DefaultMaxJobs.
func MaxJobs() (int, error) {
	return positiveEnv(EnvMaxJobs, DefaultMaxJobs)
}

// RetryAttempts returns how many attempts a network-bound step gets:
// E2E_RETRY_ATTEMPTS, or DefaultRetryAttempts.
func RetryAttempts() (int, error) {
	return positiveEnv(EnvRetryAttempts, DefaultRetryAttempts)
}

func positiveEnv(name string, def int) (int, error) {
	raw := os.Getenv(name)
	if raw == "" {
		return def, nil
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n < 1 {
		return 0, fmt.Errorf("%s=%q: want a positive integer", name, raw)
	}
	return n, nil
}

// ContainerEnv is the environment every Linux container starts with: the
// build parallelism by default, and the pass-through variables of the host.
func ContainerEnv() map[string]string {
	env := map[string]string{"MAKEFLAGS": DefaultMakeFlags}
	for _, name := range PassThroughEnvs {
		if v := os.Getenv(name); v != "" {
			env[name] = v
		}
	}
	return env
}

// ContainerName names the container of a combo. A run that was killed leaves
// containers under the vfox-php-e2e- prefix, which is what to prune.
func ContainerName(slug string) string {
	return "vfox-php-e2e-" + slug + "-" + strconv.FormatInt(time.Now().UnixNano(), 36)
}

// VersionPattern matches what `php -r 'echo PHP_VERSION;'` prints for a spec:
// latest is any release, a major.minor any patch of it, and a full release
// itself. A -zts spec is its release, since PHP_VERSION does not show the build.
func VersionPattern(spec string) (*regexp.Regexp, error) {
	if !specPattern.MatchString(spec) {
		return nil, fmt.Errorf("%q is not latest, a major, a major.minor or a full release", spec)
	}
	if spec == "latest" {
		return regexp.Compile(`^[0-9]+\.[0-9]+\.[0-9]+$`)
	}
	release := strings.TrimSuffix(spec, "-zts")
	var b strings.Builder
	b.WriteString("^")
	for i, part := range strings.Split(release, ".") {
		if i > 0 {
			b.WriteString(`\.`)
		}
		b.WriteString(regexp.QuoteMeta(part))
	}
	for parts := strings.Count(release, ".") + 1; parts < 3; parts++ {
		b.WriteString(`\.[0-9]+`)
	}
	b.WriteString("$")
	return regexp.Compile(b.String())
}

// StripANSI removes the colour and cursor sequences from vfox's output.
func StripANSI(s string) string {
	return ansiPattern.ReplaceAllString(s, "")
}

// MissingModules returns the modules of want that the listing of `php -m` does
// not name. Section headers in brackets are skipped, and names compare without case.
func MissingModules(listing string, want ...string) []string {
	have := make(map[string]bool)
	for _, line := range strings.Split(StripANSI(listing), "\n") {
		name := strings.TrimSpace(line)
		if name == "" || strings.HasPrefix(name, "[") {
			continue
		}
		have[strings.ToLower(name)] = true
	}
	var missing []string
	for _, module := range want {
		if !have[strings.ToLower(module)] {
			missing = append(missing, module)
		}
	}
	return missing
}

// ListsVersion reports whether a listing names version as a whole word, once
// colour is stripped: 8.5.0 matches "php@8.5.0", " - 8.5.0" and "8.5.0 (installed)",
// but not 8.5.0RC1 or 8.5.01.
func ListsVersion(listing, version string) bool {
	word := `(^|[^0-9A-Za-z.])` + regexp.QuoteMeta(version) + `($|[^0-9A-Za-z.])`
	return regexp.MustCompile(word).MatchString(StripANSI(listing))
}

// Retry calls fn until it returns nil or the attempts run out. It waits backoff
// after the first failure, twice backoff after the second, and so on. ctx ends
// the wait early.
func Retry(ctx context.Context, attempts int, backoff time.Duration, fn func() error) error {
	if attempts < 1 {
		attempts = 1
	}
	var err error
	for i := 1; i <= attempts; i++ {
		if err = fn(); err == nil {
			return nil
		}
		if i == attempts {
			break
		}
		timer := time.NewTimer(time.Duration(i) * backoff)
		select {
		case <-ctx.Done():
			timer.Stop()
			return fmt.Errorf("attempt %d: %w; stopped: %w", i, err, ctx.Err())
		case <-timer.C:
		}
	}
	return fmt.Errorf("failed after %d attempts: %w", attempts, err)
}

// RepoRoot returns the plugin checkout: the closest directory at or above the
// working directory that holds metadata.lua.
func RepoRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "metadata.lua")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", errors.New("no metadata.lua at or above the working directory")
		}
		dir = parent
	}
}
