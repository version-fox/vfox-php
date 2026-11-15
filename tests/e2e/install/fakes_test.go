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
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// fakeCommands maps the name that a fake answers to onto what it does. A fake
// reads the host from the FAKE_ variables of its session, and logs to FAKE_WORK.
var fakeCommands = map[string]func(args []string, stdin io.Reader, stdout io.Writer) int{
	"uname":      fakeUname,
	"brew":       fakeBrew,
	"ldconfig":   fakeLdconfig,
	"cc":         fakeCC,
	"locate":     fakeLocate,
	"make":       fakeMake,
	"autoconf":   fakeTool("autoconf"),
	"pkg-config": fakePkgConfig,
	"curl":       fakeTool("curl"),
	"configure":  fakeConfigure,
	"buildconf":  fakeBuildconf,
}

// fakeUname prints the uname of the host, as uname -a would.
func fakeUname(_ []string, _ io.Reader, stdout io.Writer) int {
	fmt.Fprintln(stdout, os.Getenv("FAKE_UNAME"))
	return 0
}

// fakeBrew answers the Homebrew commands that bin/install runs: brew --version,
// brew ls --versions NAME and brew --prefix NAME. FAKE_BREW lists the installed
// formulae as name=prefix lines, and FAKE_BREW_MISSING makes Homebrew absent.
func fakeBrew(args []string, _ io.Reader, stdout io.Writer) int {
	if os.Getenv("FAKE_BREW_MISSING") != "" {
		return 1
	}
	formulae := parseFormulae(os.Getenv("FAKE_BREW"))
	switch {
	case len(args) == 1 && args[0] == "--version":
		fmt.Fprintln(stdout, "Homebrew 4.5.0")
		return 0
	case len(args) == 3 && args[0] == "ls" && args[1] == "--versions":
		if _, ok := formulae[args[2]]; ok {
			fmt.Fprintf(stdout, "%s 1.0\n", args[2])
		}
		return 0
	case len(args) == 2 && args[0] == "--prefix":
		prefix, ok := formulae[args[1]]
		if !ok {
			return 1
		}
		fmt.Fprintln(stdout, prefix)
		return 0
	}
	return 1
}

// parseFormulae reads the installed formulae: one name=prefix pair per line.
func parseFormulae(list string) map[string]string {
	formulae := map[string]string{}
	for _, line := range strings.Split(list, "\n") {
		if name, prefix, ok := strings.Cut(line, "="); ok && name != "" {
			formulae[name] = prefix
		}
	}
	return formulae
}

// fakeLdconfig lists the libraries of the host, as ldconfig -p does.
func fakeLdconfig(_ []string, _ io.Reader, stdout io.Writer) int {
	fmt.Fprintln(stdout, os.Getenv("FAKE_LIBRARIES"))
	return 0
}

var includeLine = regexp.MustCompile(`#include <([^>]+)>`)

// fakeCC answers the tool check of bin/install, "cc --version", and its header
// check: it reads "#include <header>" on stdin, and succeeds when FAKE_HEADERS
// lists that header.
func fakeCC(args []string, stdin io.Reader, stdout io.Writer) int {
	if status, ok := answerVersion("cc", args, stdout); ok {
		return status
	}
	input, err := io.ReadAll(stdin)
	if err != nil {
		return 1
	}
	match := includeLine.FindSubmatch(input)
	if match == nil {
		return 1
	}
	for _, header := range strings.Split(os.Getenv("FAKE_HEADERS"), ",") {
		if header == string(match[1]) {
			return 0
		}
	}
	return 1
}

// fakeLocate only logs its call: bin/install must not call locate at all.
func fakeLocate(args []string, _ io.Reader, _ io.Writer) int {
	appendLog("locate.log", strings.TrimSpace("locate "+strings.Join(args, " ")))
	return 0
}

// fakeMake logs its call. make install creates the prefix that configure was
// given, as the real make install does. make --version is the tool check of
// bin/install, which is answered but not logged.
func fakeMake(args []string, _ io.Reader, stdout io.Writer) int {
	if status, ok := answerVersion("make", args, stdout); ok {
		return status
	}
	appendLog("make.log", strings.TrimSpace("make "+strings.Join(args, " ")))
	if len(args) == 1 && args[0] == "install" {
		prefix := configuredPrefix()
		if prefix == "" || os.MkdirAll(prefix, 0o755) != nil {
			return 1
		}
	}
	return 0
}

// fakeConfigure logs that it ran, then records the arguments it is given, one per
// line, in configure.args. It fails when FAKE_CONFIGURE_FAIL is set, after logging.
func fakeConfigure(args []string, _ io.Reader, _ io.Writer) int {
	appendLog("configure.log", "configure")
	if os.Getenv("FAKE_CONFIGURE_FAIL") != "" {
		return 1
	}
	var record strings.Builder
	for _, arg := range args {
		record.WriteString(arg + "\n")
	}
	if err := os.WriteFile(logPath("configure.args"), []byte(record.String()), 0o644); err != nil {
		return 1
	}
	return 0
}

// fakeBuildconf does nothing: a fake source tree needs no generated files.
func fakeBuildconf(_ []string, _ io.Reader, _ io.Writer) int {
	return 0
}

// fakeTool answers the tool check of bin/install, "name --version", for a tool
// that no other fake answers. Any other call of the tool fails.
func fakeTool(name string) func(args []string, stdin io.Reader, stdout io.Writer) int {
	return func(args []string, _ io.Reader, stdout io.Writer) int {
		if status, ok := answerVersion(name, args, stdout); ok {
			return status
		}
		return 1
	}
}

// answerVersion answers "name --version", which bin/install runs to see whether a
// tool is installed. The tool is installed when FAKE_TOOLS lists it. It reports
// false for any other call, which the caller answers.
func answerVersion(name string, args []string, stdout io.Writer) (int, bool) {
	if len(args) != 1 || args[0] != "--version" {
		return 0, false
	}
	if !hostHasTool(name) {
		return 1, true
	}
	fmt.Fprintf(stdout, "%s (fake)\n", name)
	return 0, true
}

// hostHasTool reports whether FAKE_TOOLS lists the tool.
func hostHasTool(name string) bool {
	return envListHas("FAKE_TOOLS", name)
}

// envListHas reports whether the comma-separated list in the variable has the item.
func envListHas(variable, item string) bool {
	for _, got := range strings.Split(os.Getenv(variable), ",") {
		if got == item {
			return true
		}
	}
	return false
}

// fakePkgConfig answers the tool check of bin/install, "pkg-config --version", and
// its module checks, "pkg-config --exists MODULE...". The module checks succeed when
// pkg-config is installed and FAKE_PKGS lists every module.
func fakePkgConfig(args []string, _ io.Reader, stdout io.Writer) int {
	if status, ok := answerVersion("pkg-config", args, stdout); ok {
		return status
	}
	if len(args) < 2 || args[0] != "--exists" || !hostHasTool("pkg-config") {
		return 1
	}
	for _, module := range args[1:] {
		if !envListHas("FAKE_PKGS", module) {
			return 1
		}
	}
	return 0
}

// logPath is a file of the session that the test reads back.
func logPath(name string) string {
	return filepath.Join(os.Getenv("FAKE_WORK"), name)
}

// appendLog adds a line to a log of the session.
func appendLog(name, line string) {
	file, err := os.OpenFile(logPath(name), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer file.Close()
	fmt.Fprintln(file, line)
}

// configuredPrefix returns the --prefix that configure was last given.
func configuredPrefix() string {
	data, err := os.ReadFile(logPath("configure.args"))
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(data), "\n") {
		if prefix, ok := strings.CutPrefix(line, "--prefix="); ok {
			return prefix
		}
	}
	return ""
}
