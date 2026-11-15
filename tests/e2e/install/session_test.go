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
	"bytes"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"testing"

	"github.com/version-fox/vfox-php/tests/e2e/common"
)

// host is what the fake commands report about the machine.
type host struct {
	uname     string            // what uname -a prints
	formulae  map[string]string // installed Homebrew formulae and their prefixes; nil when Homebrew is absent
	libraries string            // what ldconfig -p lists
	headers   []string          // the headers that the compiler finds
}

// linuxHost is a Linux machine with no libraries and no headers.
func linuxHost() host {
	return host{uname: "Linux test 6.8.0 x86_64 GNU/Linux"}
}

// linuxWith is a Linux machine with the given libraries and headers.
func linuxWith(libraries string, headers ...string) host {
	h := linuxHost()
	h.libraries = libraries
	h.headers = headers
	return h
}

// darwinHost is a Mac whose Homebrew has the given formulae installed.
func darwinHost(formulae map[string]string) host {
	return host{uname: "Darwin test 25.0.0 arm64", formulae: formulae}
}

// session is a run of bin/install in bash, or of a script that sources it. The
// fake commands come first on its PATH. Its working directory is a temporary
// folder, which also holds HOME and the logs that the fakes write.
type session struct {
	t    *testing.T
	work string
	env  []string
}

// newSession starts a session on the host.
func newSession(t *testing.T, h host) *session {
	t.Helper()
	requireBash(t)
	work := t.TempDir()
	bin := filepath.Join(work, "bin")
	mkdir(t, bin)
	self := testBinary(t)
	for _, name := range []string{"uname", "brew", "ldconfig", "cc", "locate", "make"} {
		if err := os.Symlink(self, filepath.Join(bin, name)); err != nil {
			t.Fatalf("link the fake %s: %v", name, err)
		}
	}
	home := filepath.Join(work, "home")
	mkdir(t, home)

	env := append(scrubbedEnv(),
		"PATH="+bin+string(os.PathListSeparator)+os.Getenv("PATH"),
		"HOME="+home,
		"FAKE_WORK="+work,
		"FAKE_UNAME="+h.uname,
		"FAKE_LIBRARIES="+h.libraries,
		"FAKE_HEADERS="+strings.Join(h.headers, ","),
		"PHP_CONFIGURE_OPTIONS=",
	)
	if h.formulae == nil {
		env = append(env, "FAKE_BREW_MISSING=1")
	} else {
		env = append(env, "FAKE_BREW="+formulaeList(h.formulae))
	}
	return &session{t: t, work: work, env: env}
}

// newHostSession starts a session on the machine the test runs on: the real
// commands, and the real environment.
func newHostSession(t *testing.T) *session {
	t.Helper()
	requireBash(t)
	return &session{t: t, work: t.TempDir(), env: append(os.Environ(), "PHP_CONFIGURE_OPTIONS=")}
}

// with returns the session with more environment variables, which override the
// ones it has.
func (s *session) with(kv ...string) *session {
	copied := *s
	copied.env = append(append([]string(nil), s.env...), kv...)
	return &copied
}

// result is what a run printed, and how it ended.
type result struct {
	stdout string
	stderr string
	status int
}

// run sources bin/install into bash, and runs script after it.
func (s *session) run(script string) result {
	s.t.Helper()
	return s.bash("set -euo pipefail\nsource " + shellQuote(installPath(s.t)) + "\n" + script)
}

// bash runs script in bash, in the folder of the session.
func (s *session) bash(script string) result {
	s.t.Helper()
	return s.command("bash", "-c", script)
}

// exec runs bin/install as a script with the arguments, as the plugin runs it.
func (s *session) exec(args ...string) result {
	s.t.Helper()
	return s.command("bash", append([]string{installPath(s.t)}, args...)...)
}

func (s *session) command(name string, args ...string) result {
	s.t.Helper()
	cmd := exec.Command(name, args...)
	cmd.Dir = s.work
	cmd.Env = s.env
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	status := 0
	if err := cmd.Run(); err != nil {
		var exitErr *exec.ExitError
		if !errors.As(err, &exitErr) {
			s.t.Fatalf("run %s: %v", name, err)
		}
		status = exitErr.ExitCode()
	}
	return result{stdout: stdout.String(), stderr: stderr.String(), status: status}
}

// fakeSource makes a PHP source tree at dir, whose buildconf and configure are
// the fake commands. bin/install builds and installs it.
func fakeSource(t *testing.T, dir string) {
	t.Helper()
	mkdir(t, dir)
	self := testBinary(t)
	for _, name := range []string{"buildconf", "configure"} {
		if err := os.Symlink(self, filepath.Join(dir, name)); err != nil {
			t.Fatalf("link the fake %s: %v", name, err)
		}
	}
}

// readArguments returns the arguments that the fake configure recorded.
func (s *session) readArguments() string {
	s.t.Helper()
	data, err := os.ReadFile(filepath.Join(s.work, "configure.args"))
	if err != nil {
		s.t.Fatalf("configure was not run: %v", err)
	}
	return string(data)
}

// installPath is bin/install of this repository.
func installPath(t *testing.T) string {
	t.Helper()
	root, err := common.RepoRoot()
	if err != nil {
		t.Fatalf("find the repository: %v", err)
	}
	return filepath.Join(root, "bin", "install")
}

// testBinary is the test binary, which the fake commands are symlinks to.
func testBinary(t *testing.T) string {
	t.Helper()
	self, err := os.Executable()
	if err != nil {
		t.Fatalf("find the test binary: %v", err)
	}
	return self
}

// requireBash skips the test on Windows, where bin/install cannot run, and fails
// when bash is missing elsewhere.
func requireBash(t *testing.T) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("bin/install is a bash script")
	}
	if _, err := exec.LookPath("bash"); err != nil {
		t.Fatalf("bash is needed to run bin/install: %v", err)
	}
}

// requireStatus fails the test unless the run ended with status want.
func requireStatus(t *testing.T, r result, want int) {
	t.Helper()
	if r.status != want {
		t.Fatalf("exit status %d, want %d\nstdout:\n%s\nstderr:\n%s", r.status, want, r.stdout, r.stderr)
	}
}

// hasLine reports whether one of the lines of text is exactly line.
func hasLine(text, line string) bool {
	for _, got := range strings.Split(text, "\n") {
		if got == line {
			return true
		}
	}
	return false
}

// shellQuote quotes s for bash.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func mkdir(t *testing.T, dir string) {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("make %s: %v", dir, err)
	}
}

// scrubbedEnv is the environment of the test, without the variables that the
// sessions set: the PHP_ and FAKE_ variables, XDG_DATA_HOME, HOME and PATH.
func scrubbedEnv() []string {
	var env []string
	for _, kv := range os.Environ() {
		name, _, _ := strings.Cut(kv, "=")
		if strings.HasPrefix(name, "PHP_") || strings.HasPrefix(name, "FAKE_") {
			continue
		}
		switch name {
		case "XDG_DATA_HOME", "HOME", "PATH":
			continue
		}
		env = append(env, kv)
	}
	return env
}

// formulaeList writes the installed formulae as the lines the fake brew reads.
func formulaeList(formulae map[string]string) string {
	lines := make([]string, 0, len(formulae))
	for name, prefix := range formulae {
		lines = append(lines, name+"="+prefix)
	}
	sort.Strings(lines)
	return strings.Join(lines, "\n")
}
