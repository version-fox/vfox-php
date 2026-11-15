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
	"io"
	"testing"

	tc "github.com/testcontainers/testcontainers-go"
	tcexec "github.com/testcontainers/testcontainers-go/exec"
)

// pwshExe is the PowerShell 7 that the image installs. Exec names it in full
// rather than rely on the machine PATH.
const pwshExe = `C:\Program Files\PowerShell\7\pwsh.exe`

// pwshPrelude makes each script stop at its first error, and puts vfox on the
// PATH whatever the machine PATH holds. Without the first, pwsh exits 0 after a
// non-terminating error, and ok would pass silently.
const pwshPrelude = `$ErrorActionPreference = 'Stop'; $PSNativeCommandUseErrorActionPreference = $true; $env:PATH = 'C:\vfox-bin;C:\Program Files\PowerShell\7;' + $env:PATH;`

// session drives one container. Every step is one pwsh exec, so a step starts
// from a fresh session, as a command typed at a prompt would.
type session struct {
	t   *testing.T
	ctx context.Context
	ctr tc.Container
}

// run executes script and returns its exit code with its combined stdout and
// stderr. Only a failure to exec at all fails the test here.
func (s *session) run(script string) (int, string) {
	s.t.Helper()
	code, r, err := s.ctr.Exec(s.ctx, []string{pwshExe, "-NoProfile", "-Command", pwshPrelude + " " + script}, tcexec.Multiplexed())
	if err != nil {
		s.t.Fatalf("exec: %v\n--- script ---\n%s", err, script)
	}
	out, err := io.ReadAll(r)
	if err != nil {
		s.t.Fatalf("read output: %v\n--- script ---\n%s", err, script)
	}
	return code, string(out)
}

// ok executes script and fails the test unless it exits 0. It returns the output.
func (s *session) ok(script string) string {
	s.t.Helper()
	code, out := s.run(script)
	if code != 0 {
		s.t.Fatalf("exit %d\n--- script ---\n%s\n--- output ---\n%s", code, script, out)
	}
	return out
}
