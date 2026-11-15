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

package linux

import (
	"context"
	"fmt"
	"strings"

	"github.com/version-fox/vfox-php/tests/e2e/common"
)

// pluginZip is the plugin archive the image builds, made as CI makes it.
const pluginZip = "/opt/php-plugin.zip"

// workDir is the project each container selects PHP in.
const workDir = "/work"

// project is the prefix of a check: it moves into the project and activates
// vfox there, as a shell does when a prompt starts in that directory.
func project() string {
	return fmt.Sprintf(`cd %s && eval "$(vfox activate bash)" && eval "$(vfox env --shell bash)" && `, workDir)
}

// checkPlugin adds the plugin from its archive, and checks that the notes
// `vfox info` prints link the README.
func checkPlugin(s *session) {
	s.t.Helper()
	s.ok("vfox add -s " + pluginZip)
	info := common.StripANSI(s.ok("vfox info php"))
	if !strings.Contains(info, common.ReadmeURL) {
		s.t.Fatalf("vfox info php does not link the README %s:\n%s", common.ReadmeURL, info)
	}
}

// checkUnknownVersion checks that PreInstall refuses a version no release has,
// and names it in the error vfox prints.
func checkUnknownVersion(s *session) {
	s.t.Helper()
	code, out := s.run("vfox install php@" + common.UnknownVersion)
	if code == 0 || !strings.Contains(common.StripANSI(out), common.UnknownVersionError) {
		s.t.Fatalf("install php@%s: exit %d, want a failure naming %q:\n%s",
			common.UnknownVersion, code, common.UnknownVersionError, out)
	}
}

// checkInstall installs the spec. PreInstall passes php.net's sha256 on for
// Linux, and vfox must verify the download with it.
func checkInstall(s *session, spec string) {
	s.t.Helper()
	out := s.ok(fmt.Sprintf("mkdir -p %[1]s && cd %[1]s && vfox install php@%[2]s", workDir, spec))
	if !strings.Contains(out, "Verifying checksum") {
		s.t.Fatalf("php@%s: vfox did not verify the download:\n%s", spec, out)
	}
}

// checkUse selects the spec in the project, the way the CI workflows do, and
// returns the version that was installed.
func checkUse(s *session, spec string) string {
	s.t.Helper()
	s.ok(fmt.Sprintf(`cd %s && eval "$(vfox activate bash)" && vfox use -p php@%s`, workDir, spec))

	php := strings.TrimSpace(s.ok(project() + "command -v php"))
	if want := workDir + "/.vfox/sdks/php/bin/php"; php != want {
		s.t.Fatalf("php resolves to %q, want %q", php, want)
	}
	version := strings.TrimSpace(s.ok(project() + `php -r 'echo PHP_VERSION;'`))
	pattern, err := common.VersionPattern(spec)
	if err != nil {
		s.t.Fatal(err)
	}
	if !pattern.MatchString(version) {
		s.t.Fatalf("php@%s installed PHP %q", spec, version)
	}
	s.t.Logf("php@%s selected PHP %s", spec, version)
	return version
}

// checkRuntime checks the PHP that was selected: its banner, its modules, the
// php.ini that bin/install leaves in the install, composer, and what vfox lists.
func checkRuntime(s *session, version string) {
	s.t.Helper()

	banner := s.ok(project() + "php -v")
	if !strings.HasPrefix(banner, "PHP "+version+" (cli)") {
		s.t.Fatalf("php -v does not start with PHP %s (cli):\n%s", version, banner)
	}

	modules := s.ok(project() + "php -m")
	if missing := common.MissingModules(modules, common.LinuxModules...); len(missing) > 0 {
		s.t.Fatalf("php -m lacks %v:\n%s", missing, modules)
	}

	// PCRE JIT is on unless the build opted out, and gd takes JPEG from the system libgd.
	if jit := strings.TrimSpace(s.ok(project() + "php -i | grep 'PCRE JIT Support'")); !strings.HasSuffix(jit, "=> enabled") {
		s.t.Fatalf("PCRE JIT is not enabled in the build: %q", jit)
	}
	if jpeg := strings.TrimSpace(s.ok(project() + `php -r 'echo gd_info()["JPEG Support"] ? "yes" : "no";'`)); jpeg != "yes" {
		s.t.Fatalf("gd reports no JPEG support: %q", jpeg)
	}

	// bin/install writes conf.d/php.ini into the install, next to bin/.
	s.ok(project() + `test -f "$(dirname "$(dirname "$(command -v php)")")/conf.d/php.ini"`)

	composer := strings.TrimSpace(s.ok(project() + "command -v composer"))
	if want := workDir + "/.vfox/sdks/php/bin/composer"; composer != want {
		s.t.Fatalf("composer resolves to %q, want %q", composer, want)
	}
	if out := s.ok(project() + "composer -V"); !strings.Contains(out, "Composer version") {
		s.t.Fatalf("composer -V printed %q", out)
	}

	listed := s.ok(project() + "vfox list php")
	if !common.ListsVersion(listed, version) {
		s.t.Fatalf("vfox list php does not list %s:\n%s", version, listed)
	}
}

// checkSearch checks that `vfox search` lists the installed version. The
// listing asks php.net, so it gets the retries.
func checkSearch(ctx context.Context, s *session, version string, attempts int) {
	s.t.Helper()
	err := common.Retry(ctx, attempts, common.RetryBackoff, func() error {
		code, out := s.run("vfox search php")
		switch {
		case code != 0:
			return fmt.Errorf("vfox search exited %d:\n%s", code, out)
		case !common.ListsVersion(out, version):
			return fmt.Errorf("vfox search does not list %s:\n%s", version, out)
		}
		return nil
	})
	if err != nil {
		s.t.Fatal(err)
	}
}
