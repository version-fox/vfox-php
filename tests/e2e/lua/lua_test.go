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

// Package lua runs the Lua unit tests of the plugin, the files tests/*_test.lua. Each file
// is a subtest of TestLua, and runs in its own gopher-lua state: the interpreter that vfox
// runs the plugin with, set up the way the glua command sets it up. go test -short ./... in
// tests/e2e runs these with the Go unit tests, so a new *_test.lua file needs no change here
// or in CI.
package lua

import (
	"path/filepath"
	"testing"

	lua "github.com/yuin/gopher-lua"
)

// TestLua runs every tests/*_test.lua file. The tests load ./lib and open files by relative
// path, so they run from the repository root, as they do under glua.
func TestLua(t *testing.T) {
	// go test runs this package in tests/e2e/lua, three levels below the repository root.
	t.Chdir(filepath.Join("..", "..", ".."))
	files, err := filepath.Glob(filepath.Join("tests", "*_test.lua"))
	if err != nil {
		t.Fatal(err)
	}
	if len(files) == 0 {
		t.Fatal("no Lua unit tests found in tests/")
	}
	for _, file := range files {
		t.Run(filepath.Base(file), func(t *testing.T) {
			L := lua.NewState()
			defer L.Close()
			L.SetGlobal("arg", L.NewTable())
			if err := L.DoFile(file); err != nil {
				t.Fatal(err)
			}
		})
	}
}
