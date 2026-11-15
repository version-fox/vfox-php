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

// TestE2E builds the image from tests/e2e/linux/Dockerfile and runs one
// container per PHP version of the matrix.
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

	// PHP cannot be installed into a path with spaces, so the plugin refuses one.
	t.Run("VFOX_HOME with a space is refused", func(t *testing.T) {
		runSpacedHome(ctx, t, image, platform)
	})

	sem := make(chan struct{}, jobs)
	for _, c := range combos {
		t.Run(c.Slug(), func(t *testing.T) {
			t.Parallel()
			sem <- struct{}{}
			defer func() { <-sem }()
			runOne(ctx, t, image, platform, c, attempts)
		})
	}
}

// spacedHome is a VFOX_HOME with a space in it. PHP's make install cannot
// install into such a path, so the plugin must stop before it compiles.
const spacedHome = "/root/vfox home"

// spacedPathMessage is the part of the refusal that names the reason.
const spacedPathMessage = "cannot be installed into a path with spaces"

// runSpacedHome starts a container whose VFOX_HOME holds a space, and checks
// that the install stops with the reason. The archive download comes first, and
// the refusal comes before the compile, so this takes about a minute.
func runSpacedHome(ctx context.Context, t *testing.T, image, platform string) {
	t.Helper()
	ctr, err := tc.GenericContainer(ctx, tc.GenericContainerRequest{
		ContainerRequest: tc.ContainerRequest{
			Image:         image,
			ImagePlatform: platform,
			Name:          common.ContainerName("spaced-home"),
			Env:           map[string]string{"VFOX_HOME": spacedHome},
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
	s.ok("vfox add -s " + pluginZip)

	code, out := s.run("vfox install php@8.3")
	if code == 0 || !strings.Contains(common.StripANSI(out), spacedPathMessage) {
		t.Fatalf("install into %q: exit %d, want a refusal that says why:\n%s", spacedHome, code, out)
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
	checkRuntime(s, version)
	checkSearch(ctx, s, version, attempts)
}
