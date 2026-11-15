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
	"os"
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
	// baseImage must match the Windows Server build of the host: process
	// isolation needs the same release on both sides. PHP publishes Windows
	// builds for x64 and x86 only, so this suite is x64.
	baseImage = "mcr.microsoft.com/windows/servercore:ltsc2025-KB5122871-amd64"
	platform  = "windows/amd64"
	// vfoxHome holds a space on purpose: vfox has to cope with it.
	vfoxHome = `C:\vfox home`
	// comboBudget bounds the whole flow of one container.
	comboBudget = 45 * time.Minute
)

// TestE2E builds the image from tests/e2e/windows/Dockerfile and runs one
// container per PHP version of the matrix. It needs a Windows host with Docker
// in Windows-container mode.
func TestE2E(t *testing.T) {
	if testing.Short() {
		t.Skip("container E2E skipped in -short mode")
	}
	// Ryuk has no Windows image, so the reaper can never start here. Every
	// container is terminated explicitly via t.Cleanup instead.
	t.Setenv("TESTCONTAINERS_RYUK_DISABLED", "true")

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
	image := buildImage(ctx, t, root)

	sem := make(chan struct{}, jobs)
	for _, c := range combos {
		t.Run(c.Slug(), func(t *testing.T) {
			t.Parallel()
			sem <- struct{}{}
			defer func() { <-sem }()
			runOne(ctx, t, image, c, attempts)
		})
	}
}

// buildImage builds the image the way docker build does: the checkout is the
// context, and the image carries it as the plugin.
func buildImage(ctx context.Context, t *testing.T, root string) string {
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

	tag := "windows-amd64"
	image := imageRepo + ":" + tag
	base := baseImage
	built, err := provider.BuildImage(ctx, &tc.ContainerRequest{
		FromDockerfile: tc.FromDockerfile{
			Context:        root,
			Dockerfile:     "tests/e2e/windows/Dockerfile",
			Repo:           imageRepo,
			Tag:            tag,
			BuildArgs:      map[string]*string{"BASE_IMAGE": &base},
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
// plugin, an unknown version, the Visual C++ runtime before the install, the
// install, the runtime after it, the selection, the TS runtime, the NTS build
// and the search. Each step asserts what it finds, and a failure stops the combo.
func runOne(ctx context.Context, t *testing.T, image string, c common.Combo, attempts int) {
	t.Helper()

	// Stock Windows daemons have no "bridge" network, only "nat", and
	// CreateContainer creates the provider's default bridge network when it is
	// missing. Point it at "nat", the daemon default that docker run uses, or
	// every start fails with "could not find plugin bridge".
	provider, err := tc.NewDockerProvider(tc.WithDefaultBridgeNetwork("nat"))
	if err != nil {
		t.Fatalf("[php@%s] new docker provider: %v", c.Spec, err)
	}
	ctr, err := provider.RunContainer(ctx, tc.ContainerRequest{
		Image:         image,
		ImagePlatform: platform,
		Name:          common.ContainerName(c.Slug()),
		Env:           map[string]string{"VFOX_HOME": vfoxHome},
	})
	if err != nil {
		t.Fatalf("[php@%s] start container: %v", c.Spec, err)
	}
	t.Cleanup(func() { _ = ctr.Terminate(context.Background()) })

	ctx, cancel := context.WithTimeout(ctx, comboBudget)
	defer cancel()
	s := &session{t: t, ctx: ctx, ctr: ctr}

	t.Logf("=== php@%s on %s ===", c.Spec, platform)

	// vfox creates the plugin folder inside VFOX_HOME, but it does not create
	// VFOX_HOME itself: the first `vfox add` fails without these folders.
	s.ok(fmt.Sprintf("New-Item -ItemType Directory -Force -Path '%s', '%s\\plugin' | Out-Null", vfoxHome, vfoxHome))

	checkPlugin(s)
	checkUnknownVersion(s)
	checkRuntimeOnPath(s, false)
	install := checkInstall(s, c.Spec)
	checkRuntimeOnPath(s, true)
	checkRedistInstalled(s, install)
	version := checkUse(s, c.Spec)
	checkRuntime(s, version)
	checkNTS(s, version)
	checkDetectedLink(s, version)
	checkSearch(ctx, s, version, attempts)

	t.Logf("php@%s: all checks passed (%s)", c.Spec, strings.TrimSpace(version))
}
