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

// checkInstall installs the spec, and returns the output of the install. Windows
// releases carry no checksum in PreInstall, so vfox has nothing to verify here.
func checkInstall(s *session, spec string) string {
	s.t.Helper()
	return s.ok(fmt.Sprintf(`Set-Location '%s'; vfox install 'php@%s'`, workDir, spec))
}

// vcRuntimeDLL is the Visual C++ 2015-2022 runtime file that the x64 PHP builds load.
const vcRuntimeDLL = "vcruntime140.dll"

// redistHelper is the PowerShell script that the plugin's install runs, through a
// batch file, to install the runtime. The batch file echoes its command, so the name
// shows in the output of the install that runs it.
const redistHelper = "install_vc_redist.ps1"

// checkRedistInstalled checks that the install installed the runtime itself: its
// output shows the helper that the plugin runs for that.
func checkRedistInstalled(s *session, install string) {
	s.t.Helper()
	if !strings.Contains(install, redistHelper) {
		s.t.Fatalf("the install did not run %s, so it did not install the runtime:\n%s", redistHelper, install)
	}
}

// checkRuntimeOnPath checks the Visual C++ runtime that the PHP builds load. The
// image has none, and no folder that the loader searches may hold it before the
// install: the plugin brings it in when php.exe does not start. After the install,
// System32 holds it. The search covers System32, the Windows folder and every PATH
// folder, as the loader does for php.exe.
func checkRuntimeOnPath(s *session, installed bool) {
	s.t.Helper()
	if installed {
		got := strings.TrimSpace(s.ok(fmt.Sprintf(`Test-Path -LiteralPath (Join-Path $env:SystemRoot 'System32\%s')`, vcRuntimeDLL)))
		if got != "True" {
			s.t.Fatalf("System32 has no %s after the install (Test-Path = %q)", vcRuntimeDLL, got)
		}
		return
	}
	found := strings.TrimSpace(s.ok(fmt.Sprintf(`$dirs = @((Join-Path $env:SystemRoot 'System32'), $env:SystemRoot) + ($env:PATH -split ';'); $dirs | Where-Object { $_ } | ForEach-Object { Join-Path $_ '%s' } | Where-Object { Test-Path -LiteralPath $_ }`, vcRuntimeDLL)))
	if found != "" {
		s.t.Fatalf("the runtime is on the search path before the install, so the install would not bring it in:\n%s", found)
	}
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
	// PHP 8.5 defines PHP_ZTS as a bool (true prints 1, false prints nothing);
	// earlier versions define an int. (int) gives 1 or 0 for both.
	if zts := strings.TrimSpace(s.ok(project + "php -r 'echo (int) PHP_ZTS;'")); zts != "1" {
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
	out := s.ok(fmt.Sprintf(`New-Item -ItemType Directory -Force -Path '%s' | Out-Null; Set-Location '%s'; vfox install 'php@%s-nts'; vfox use -p 'php@%s-nts'`, ntsDir, ntsDir, version, version))
	// The runtime is recorded by now, so this install must not run its installer again.
	if strings.Contains(out, redistHelper) {
		s.t.Fatalf("the -nts install ran %s again, although the runtime is recorded:\n%s", redistHelper, out)
	}

	project := selectIn(ntsDir)
	if zts := strings.TrimSpace(s.ok(project + "php -r 'echo (int) PHP_ZTS;'")); zts != "0" {
		s.t.Fatalf("PHP_ZTS = %q for the -nts build, want 0", zts)
	}
	if got := strings.TrimSpace(s.ok(project + "php -r 'echo PHP_VERSION;'")); got != version {
		s.t.Fatalf("the -nts build reports PHP %q, want %s", got, version)
	}
}

// systemPHPWin is a folder of its own at the root of C:, where a PHP installed by
// hand would be. The run keeps a copy of its TS build there, so that
// `vfox link --detect` has an install to find that vfox did not make.
const systemPHPWin = `C:\php-system`

// checkDetectedLink checks that `vfox link --detect` finds a copy of the TS build
// in systemPHPWin and links it under the version name, that vfox runs it, and that
// uninstalling the link leaves the copy where it is. The copy is made from vfox's
// own TS install, which is then uninstalled, so the detection is not of vfox's copy.
func checkDetectedLink(s *session, version string) {
	s.t.Helper()
	s.ok(fmt.Sprintf(`$exe = (Get-ChildItem -Path $env:VFOX_HOME -Recurse -Filter php.exe | Where-Object { $_.Directory.Name -notmatch '-nts' } | Select-Object -First 1).Directory.FullName; Copy-Item -Recurse -Force $exe '%s'`, systemPHPWin))
	if got := strings.TrimSpace(s.ok(fmt.Sprintf(`& '%s\php.exe' -r 'echo PHP_VERSION;'`, systemPHPWin))); got != version {
		s.t.Fatalf("the copy in %s runs PHP %q, want %q", systemPHPWin, got, version)
	}
	s.ok(fmt.Sprintf(`vfox uninstall 'php@%s'`, version))

	linked := common.StripANSI(s.ok("vfox link --detect -y php"))
	if !strings.Contains(linked, systemPHPWin) {
		s.t.Fatalf("vfox link --detect did not link %s:\n%s", systemPHPWin, linked)
	}
	listed := common.StripANSI(s.ok("vfox list php"))
	if !strings.Contains(listed, "linked") || !strings.Contains(listed, systemPHPWin) {
		s.t.Fatalf("vfox list php does not show the link to %s:\n%s", systemPHPWin, listed)
	}

	s.ok(fmt.Sprintf(`Set-Location '%s'; vfox use -p 'php@%s'`, workDir, version))
	project := selectIn(workDir)
	if got := strings.TrimSpace(s.ok(project + "php -r 'echo PHP_VERSION;'")); got != version {
		s.t.Fatalf("the linked PHP runs %q, want %q", got, version)
	}
	s.ok(fmt.Sprintf(`vfox uninstall 'php@%s'`, version))
	if exists := strings.TrimSpace(s.ok(fmt.Sprintf(`Test-Path '%s\php.exe'`, systemPHPWin))); exists != "True" {
		s.t.Fatalf("uninstalling the link removed the copy in %s", systemPHPWin)
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
