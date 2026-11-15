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
	"io"
	"testing"

	tc "github.com/testcontainers/testcontainers-go"
	tcexec "github.com/testcontainers/testcontainers-go/exec"
)

// session drives one container. Every step is one `bash -c` exec, so a step
// starts from a fresh shell, as a command typed at a prompt would.
type session struct {
	t   *testing.T
	ctx context.Context
	ctr tc.Container
}

// run executes script and returns its exit code with its combined stdout and
// stderr. Only a failure to exec at all fails the test here.
func (s *session) run(script string) (int, string) {
	s.t.Helper()
	code, r, err := s.ctr.Exec(s.ctx, []string{"bash", "-c", script}, tcexec.Multiplexed())
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
