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
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
)

// docFiles lists the Markdown pages of the repository: both READMEs, and every
// page under docs/ and docs/zh-CN/.
func docFiles(t *testing.T) []string {
	t.Helper()
	root, err := RepoRoot()
	if err != nil {
		t.Fatal(err)
	}
	files := []string{filepath.Join(root, "README.md"), filepath.Join(root, "README_CN.md")}
	for _, dir := range []string{filepath.Join(root, "docs"), filepath.Join(root, "docs", "zh-CN")} {
		files = append(files, markdownIn(t, dir)...)
	}
	return files
}

func markdownIn(t *testing.T, dir string) []string {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	var files []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".md") {
			files = append(files, filepath.Join(dir, e.Name()))
		}
	}
	return files
}

// TestNotesLinkTheReadme checks the notes `vfox info` prints against the README
// they name, since the notes are the first thing a user reads.
func TestNotesLinkTheReadme(t *testing.T) {
	root, err := RepoRoot()
	if err != nil {
		t.Fatal(err)
	}
	metadata, err := os.ReadFile(filepath.Join(root, "metadata.lua"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(metadata), ReadmeURL) {
		t.Fatalf("metadata.lua does not name %s", ReadmeURL)
	}
}

// TestDocsArePaired checks that every English page under docs/ has its Chinese
// page under docs/zh-CN/, and the other way round.
func TestDocsArePaired(t *testing.T) {
	root, err := RepoRoot()
	if err != nil {
		t.Fatal(err)
	}
	names := func(files []string) []string {
		out := make([]string, 0, len(files))
		for _, f := range files {
			out = append(out, filepath.Base(f))
		}
		slices.Sort(out)
		return out
	}
	english := names(markdownIn(t, filepath.Join(root, "docs")))
	chinese := names(markdownIn(t, filepath.Join(root, "docs", "zh-CN")))
	if !slices.Equal(english, chinese) {
		t.Fatalf("docs/ and docs/zh-CN/ differ:\n  docs:       %v\n  docs/zh-CN: %v", english, chinese)
	}
	for _, readme := range []string{"README.md", "README_CN.md"} {
		if _, err := os.Stat(filepath.Join(root, readme)); err != nil {
			t.Fatal(err)
		}
	}
}

// TestDocsSwitchLanguage checks that each page links to its other language near
// the top, where a reader looks first.
func TestDocsSwitchLanguage(t *testing.T) {
	for _, file := range docFiles(t) {
		data, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		lines := strings.Split(string(data), "\n")
		head := strings.Join(lines[:min(4, len(lines))], "\n")
		if !strings.Contains(head, "[中文](") || !strings.Contains(head, "[English](") {
			t.Errorf("%s: no language switch between [中文] and [English] in its first lines", file)
		}
	}
}

var linkPattern = regexp.MustCompile(`\]\(([^)\s]+)\)`)

// TestDocLinksResolve checks that every relative link in the documentation
// points at a file that exists. Web links and in-page anchors are not checked.
func TestDocLinksResolve(t *testing.T) {
	for _, file := range docFiles(t) {
		data, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		for _, m := range linkPattern.FindAllStringSubmatch(string(data), -1) {
			target := m[1]
			if strings.HasPrefix(target, "http://") || strings.HasPrefix(target, "https://") ||
				strings.HasPrefix(target, "mailto:") || strings.HasPrefix(target, "#") {
				continue
			}
			if i := strings.Index(target, "#"); i >= 0 {
				target = target[:i]
			}
			if _, err := os.Stat(filepath.Join(filepath.Dir(file), target)); err != nil {
				t.Errorf("%s links %q, which does not exist", file, m[1])
			}
		}
	}
}
