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

// Package install tests bin/install, the build script of the plugin, on a host
// that has none of the libraries it looks for. bin/install runs under bash, and
// the commands it calls on the host (uname, brew, ldconfig, cc, locate and make,
// and the buildconf and configure of a PHP source tree) are replaced: each is a
// symlink to this test binary, which answers as the command it was called as. See
// fakes_test.go.
package install

import (
	"os"
	"path/filepath"
	"testing"
)

func TestMain(m *testing.M) {
	if run, ok := fakeCommands[filepath.Base(os.Args[0])]; ok {
		os.Exit(run(os.Args[1:], os.Stdin, os.Stdout))
	}
	os.Exit(m.Run())
}
