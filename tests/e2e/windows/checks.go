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

package windows

import (
	"context"
	"fmt"
	"regexp"
	"strings"

	"github.com/version-fox/vfox-php/tests/e2e/common"
)

const (
	// pluginZip is the plugin archive the image builds, made as CI makes it.
	pluginZip = `C:\php-plugin.zip`
	// workDir is the project the TS build is selected in.
	workDir = `C:\work`
	// ntsDir is the project the NTS build is selected in, so the two selections
	// do not share a project file.
	ntsDir = `C:\work-nts`
)

// absoluteDir matches a Windows path that starts at a drive.
var absoluteDir = regexp.MustCompile(`^[A-Za-z]:[/\\]`)

// selectIn is the prefix of a check: it moves into dir and activates vfox
// there, as a prompt does when it starts in that directory.
func selectIn(dir string) string {
	return fmt.Sprintf(`Set-Location '%s'; Invoke-Expression (vfox activate pwsh | Out-String); `, dir)
}

// checkPlugin adds the plugin from its archive, and checks that the notes
// `vfox info` prints link the README.
func checkPlugin(s *session) {
	s.t.Helper()
	s.ok(`vfox add -s '` + pluginZip + `'`)
	info := common.StripANSI(s.ok("vfox info php"))
	if !strings.Contains(info, common.ReadmeURL) {
		s.t.Fatalf("vfox info php does not link the README %s:\n%s", common.ReadmeURL, info)
	}
}

// checkUnknownVersion checks that PreInstall refuses a version no release has,
// and names it in the error vfox prints.
func checkUnknownVersion(s *session) {
	s.t.Helper()
	code, out := s.run(`vfox install 'php@` + common.UnknownVersion + `'`)
	if code == 0 || !strings.Contains(common.StripANSI(out), common.UnknownVersionError) {
		s.t.Fatalf("install php@%s: exit %d, want a failure naming %q:\n%s",
			common.UnknownVersion, code, common.UnknownVersionError, out)
	}
}

// checkInstall installs the spec. Windows releases carry no checksum in
// PreInstall, so vfox has nothing to verify here.
func checkInstall(s *session, spec string) {
	s.t.Helper()
	s.ok(fmt.Sprintf(`Set-Location '%s'; vfox install 'php@%s'`, workDir, spec))
}

// checkUse selects the spec in the project, the way the CI workflow does, and
// returns the version that was installed.
func checkUse(s *session, spec string) string {
	s.t.Helper()
	s.ok(fmt.Sprintf(`Set-Location '%s'; vfox use -p 'php@%s'`, workDir, spec))

	project := selectIn(workDir)
	php := strings.TrimSpace(s.ok(project + "(Get-Command php).Source"))
	if !strings.HasSuffix(strings.ToLower(php), `\php.exe`) {
		s.t.Fatalf("php resolves to %q, want a php.exe", php)
	}
	version := strings.TrimSpace(s.ok(project + "php -r 'echo PHP_VERSION;'"))
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

// checkRuntime checks the TS build that was selected: its banner, its thread
// safety, its modules, the php.ini the plugin wrote, composer and what vfox lists.
func checkRuntime(s *session, version string) {
	s.t.Helper()
	project := selectIn(workDir)

	banner := s.ok(project + "php -v")
	if !strings.HasPrefix(banner, "PHP "+version+" (cli)") {
		s.t.Fatalf("php -v does not start with PHP %s (cli):\n%s", version, banner)
	}

	// The plugin lists TS builds under the plain version, so this one is thread-safe.
	if zts := strings.TrimSpace(s.ok(project + "php -r 'echo PHP_ZTS;'")); zts != "1" {
		s.t.Fatalf("PHP_ZTS = %q for the plain version, want 1 (thread-safe)", zts)
	}

	modules := s.ok(project + "php -m")
	if missing := common.MissingModules(modules, common.WindowsModules...); len(missing) > 0 {
		s.t.Fatalf("php -m lacks %v:\n%s", missing, modules)
	}

	// The plugin writes php.ini beside php.exe, with an absolute extension_dir.
	ini := strings.TrimSpace(s.ok(project + "php -r 'echo php_ini_loaded_file();'"))
	if !strings.HasSuffix(strings.ToLower(ini), `\php.ini`) {
		s.t.Fatalf("php loads %q, want the php.ini the plugin wrote", ini)
	}
	if !extensionDirIsAbsolute(s.ok(project + "php -i")) {
		s.t.Fatal("php -i does not show an absolute extension_dir")
	}

	composer := strings.TrimSpace(s.ok(project + "(Get-Command composer).Source"))
	if !strings.HasSuffix(strings.ToLower(composer), `\composer.bat`) {
		s.t.Fatalf("composer resolves to %q, want composer.bat", composer)
	}
	if out := s.ok(project + "composer -V"); !strings.Contains(out, "Composer version") {
		s.t.Fatalf("composer -V printed %q", out)
	}

	listed := s.ok(project + "vfox list php")
	if !common.ListsVersion(listed, version) {
		s.t.Fatalf("vfox list php does not list %s:\n%s", version, listed)
	}
}

// extensionDirIsAbsolute reads the extension_dir line of `php -i`, which shows
// the value set in php.ini and the value in use.
func extensionDirIsAbsolute(info string) bool {
	for _, line := range strings.Split(info, "\n") {
		rest, ok := strings.CutPrefix(strings.TrimSpace(line), "extension_dir => ")
		if !ok {
			continue
		}
		value := strings.SplitN(rest, " => ", 2)[0]
		return absoluteDir.MatchString(value)
	}
	return false
}

// checkNTS installs the NTS build of the version that was selected, in a
// project of its own, and checks that PHP reports itself non-thread-safe.
func checkNTS(s *session, version string) {
	s.t.Helper()
	// The project folder is made here: nothing in the image creates it.
	s.ok(fmt.Sprintf(`New-Item -ItemType Directory -Force -Path '%s' | Out-Null; Set-Location '%s'; vfox install 'php@%s-nts'; vfox use -p 'php@%s-nts'`, ntsDir, ntsDir, version, version))

	project := selectIn(ntsDir)
	if zts := strings.TrimSpace(s.ok(project + "php -r 'echo PHP_ZTS;'")); zts != "0" {
		s.t.Fatalf("PHP_ZTS = %q for the -nts build, want 0", zts)
	}
	if got := strings.TrimSpace(s.ok(project + "php -r 'echo PHP_VERSION;'")); got != version {
		s.t.Fatalf("the -nts build reports PHP %q, want %s", got, version)
	}
}

// checkSearch checks that `vfox search` lists the installed version. The
// listing asks windows.php.net, so it gets the retries.
func checkSearch(ctx context.Context, s *session, version string, attempts int) {
	s.t.Helper()
	err := common.Retry(ctx, attempts, common.RetryBackoff, func() error {
		code, out := s.run(`vfox search 'php'`)
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
