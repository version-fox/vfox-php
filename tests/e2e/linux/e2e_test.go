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
	"os"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/containerd/platforms"
	"github.com/moby/moby/client"
	specs "github.com/opencontainers/image-spec/specs-go/v1"
	tc "github.com/testcontainers/testcontainers-go"

	"github.com/version-fox/vfox-php/tests/e2e/common"
)

const (
	// imageRepo names the image the containers run.
	imageRepo = "vfox-php-e2e"
	// comboBudget bounds the whole flow of one container, the PHP build included.
	comboBudget = 45 * time.Minute
)

const (
	// spacedHome is a VFOX_HOME whose name holds a space, as a home directory
	// with a space gives one.
	spacedHome = "/root/vfox home"
	// spacedSpec is the PHP version that the spaced home installs.
	spacedSpec = "latest"
	// spacedSlug names the spaced-home run in the test output.
	spacedSlug = "VFOX_HOME with a space"
	// buildBase is the directory bin/install builds PHP in for that home: the
	// data directory under HOME, which has no space.
	buildBase = "/root/.local/share/vfox-php"
)

// TestE2E builds the image from tests/e2e/linux/Dockerfile and runs one
// container for a VFOX_HOME with a space, and one container per PHP version of
// the matrix.
func TestE2E(t *testing.T) {
	if testing.Short() {
		t.Skip("container E2E skipped in -short mode")
	}
	combos, err := common.Matrix()
	if err != nil {
		t.Fatal(err)
	}
	jobs, err := common.MaxJobs()
	if err != nil {
		t.Fatal(err)
	}
	attempts, err := common.RetryAttempts()
	if err != nil {
		t.Fatal(err)
	}
	root, err := common.RepoRoot()
	if err != nil {
		t.Fatal(err)
	}

	ctx := context.Background()
	platform := "linux/" + runtime.GOARCH
	image := buildImage(ctx, t, root, platform)

	sem := make(chan struct{}, jobs)
	t.Run(spacedSlug, func(t *testing.T) {
		t.Parallel()
		sem <- struct{}{}
		defer func() { <-sem }()
		runSpacedHome(ctx, t, image, platform, attempts)
	})
	for _, c := range combos {
		t.Run(c.Slug(), func(t *testing.T) {
			t.Parallel()
			sem <- struct{}{}
			defer func() { <-sem }()
			runOne(ctx, t, image, platform, c, attempts)
		})
	}
}

// runSpacedHome installs PHP into a VFOX_HOME with a space. The build turns PCRE
// JIT off, so the opt-out is checked by the same install. The run then checks
// that the install path links to a build directory outside the space, and that
// uninstall removes both the link and the build directory.
func runSpacedHome(ctx context.Context, t *testing.T, image, platform string, attempts int) {
	t.Helper()
	env := common.ContainerEnv()
	env["VFOX_HOME"] = spacedHome
	env["PHP_WITHOUT_PCRE_JIT"] = "yes"
	ctr, err := tc.GenericContainer(ctx, tc.GenericContainerRequest{
		ContainerRequest: tc.ContainerRequest{
			Image:         image,
			ImagePlatform: platform,
			Name:          common.ContainerName("spaced-home"),
			Env:           env,
		},
		Started: true,
	})
	if err != nil {
		t.Fatalf("start container: %v", err)
	}
	t.Cleanup(func() { _ = ctr.Terminate(context.Background()) })

	ctx, cancel := context.WithTimeout(ctx, comboBudget)
	defer cancel()
	s := &session{t: t, ctx: ctx, ctr: ctr}

	// vfox adds a plugin into VFOX_HOME/plugin, and does not create the home itself.
	s.ok("mkdir -p '" + spacedHome + "/plugin'")
	checkPlugin(s)
	checkUnknownVersion(s)
	checkInstall(s, spacedSpec)
	checkBuildLink(s)
	version := checkUse(s, spacedSpec)
	checkRuntime(s, version, pcreJITNotCompiled)
	checkSearch(ctx, s, version, attempts)
	checkUninstall(s, version)
}

// checkBuildLink checks that the install path in the spaced home is the one
// link there, and that it points at a build directory without spaces.
func checkBuildLink(s *session) {
	s.t.Helper()
	targets := strings.TrimSpace(s.ok("find '" + spacedHome + "' -type l -exec readlink {} +"))
	if !strings.HasPrefix(targets, buildBase+"/builds/") || strings.ContainsAny(targets, " \n") {
		s.t.Fatalf("the install path should link to one build directory without spaces, got:\n%s", targets)
	}
}

// checkUninstall removes the version, and checks that the link and the build
// directory it pointed to are both gone.
func checkUninstall(s *session, version string) {
	s.t.Helper()
	if code, out := s.run("vfox uninstall php@" + version); code != 0 {
		s.t.Fatalf("vfox uninstall php@%s: exit %d:\n%s", version, code, out)
	}
	if links := strings.TrimSpace(s.ok("find '" + spacedHome + "' -type l")); links != "" {
		s.t.Fatalf("links left after uninstall:\n%s", links)
	}
	builds := s.ok("if [ -d '" + buildBase + "/builds' ]; then ls -A '" + buildBase + "/builds'; fi")
	if strings.TrimSpace(builds) != "" {
		s.t.Fatalf("build directories left after uninstall:\n%s", builds)
	}
}

// buildImage builds the image the way docker build does: the checkout is the
// context, and the image carries it as the plugin.
func buildImage(ctx context.Context, t *testing.T, root, platform string) string {
	t.Helper()

	provider, err := tc.NewDockerProvider()
	if err != nil {
		t.Fatalf("new docker provider: %v", err)
	}
	t.Cleanup(func() { _ = provider.Close() })

	pf, err := platforms.Parse(platform)
	if err != nil {
		t.Fatalf("invalid platform %s: %v", platform, err)
	}

	tag := "linux-" + runtime.GOARCH
	image := imageRepo + ":" + tag
	built, err := provider.BuildImage(ctx, &tc.ContainerRequest{
		FromDockerfile: tc.FromDockerfile{
			Context:        root,
			Dockerfile:     "tests/e2e/linux/Dockerfile",
			Repo:           imageRepo,
			Tag:            tag,
			KeepImage:      true,
			BuildLogWriter: os.Stdout,
			BuildOptionsModifier: func(opts *client.ImageBuildOptions) {
				opts.Platforms = []specs.Platform{pf}
				opts.PullParent = true
			},
		},
	})
	if err != nil {
		t.Fatalf("build image %s: %v", image, err)
	}
	if built != image {
		t.Fatalf("built %s, want %s", built, image)
	}
	return image
}

// runOne starts the container of one combo and runs its checks in order: the
// plugin, an unknown version, the install, the selection, the runtime and the
// search. Each step asserts what it finds, and a failure stops the combo.
func runOne(ctx context.Context, t *testing.T, image, platform string, c common.Combo, attempts int) {
	t.Helper()
	ctr, err := tc.GenericContainer(ctx, tc.GenericContainerRequest{
		ContainerRequest: tc.ContainerRequest{
			Image:         image,
			ImagePlatform: platform,
			Name:          common.ContainerName(c.Slug()),
			Env:           common.ContainerEnv(),
		},
		Started: true,
	})
	if err != nil {
		t.Fatalf("[php@%s] start container: %v", c.Spec, err)
	}
	t.Cleanup(func() { _ = ctr.Terminate(context.Background()) })

	ctx, cancel := context.WithTimeout(ctx, comboBudget)
	defer cancel()
	s := &session{t: t, ctx: ctx, ctr: ctr}

	machine := strings.TrimSpace(s.ok("uname --machine"))
	t.Logf("=== php@%s on %s (%s) ===", c.Spec, platform, machine)

	checkPlugin(s)
	checkUnknownVersion(s)
	checkInstall(s, c.Spec)
	version := checkUse(s, c.Spec)
	checkRuntime(s, version, pcreJITEnabled)
	checkSearch(ctx, s, version, attempts)
}
