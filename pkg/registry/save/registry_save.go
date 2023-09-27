// Copyright © 2021 sealos.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package save

import (
	"context"
	"fmt"
	"github.com/containers/image/v5/transports/alltransports"
	"strings"
	stdsync "sync"
	"time"

	"github.com/containers/image/v5/copy"
	itype "github.com/containers/image/v5/types"
	v1 "github.com/opencontainers/image-spec/specs-go/v1"
	"golang.org/x/sync/errgroup"

	"github.com/labring/sreg/pkg/registry/handler"
	"github.com/labring/sreg/pkg/registry/sync"
	httputils "github.com/labring/sreg/pkg/utils/http"
	"github.com/labring/sreg/pkg/utils/logger"
)

const localhost = "127.0.0.1"

func (is *tmpRegistryImage) SaveImages(images []string, dir string, platform v1.Platform) ([]string, error) {
	logger.Debug("trying to save images: %+v for platform: %s", images,
		strings.Join([]string{platform.OS, platform.Architecture, platform.Variant}, ","))
	config, err := handler.NewConfig(dir, 0)
	if err != nil {
		return nil, err
	}
	config.Log.AccessLog.Disabled = true
	errCh := handler.Run(is.ctx, config)

	probeCtx, cancel := context.WithTimeout(is.ctx, time.Second*3)
	defer cancel()
	ep := sync.ParseRegistryAddress(localhost, config.HTTP.Addr)
	if err = httputils.WaitUntilEndpointAlive(probeCtx, "http://"+ep); err != nil {
		return nil, err
	}

	if platform.OS == "" {
		platform.OS = "linux"
	}
	sys := &itype.SystemContext{
		ArchitectureChoice:          platform.Architecture,
		OSChoice:                    platform.OS,
		VariantChoice:               platform.Variant,
		DockerInsecureSkipTLSVerify: itype.OptionalBoolTrue,
	}
	eg, _ := errgroup.WithContext(is.ctx)
	numCh := make(chan struct{}, is.maxPullProcs)
	var outImages []string
	var mu stdsync.Mutex
	for index := range images {
		img := images[index]
		numCh <- struct{}{}
		eg.Go(func() error {
			mu.Lock()
			defer func() {
				<-numCh
				mu.Unlock()
			}()
			var srcRef itype.ImageReference
			if strings.HasPrefix(img, "containers-storage") || strings.HasPrefix(img, "docker-daemon") {
				srcRef, err = alltransports.ParseImageName(img)
				if err != nil {
					return err
				}
			} else {
				srcRef, err = sync.ImageNameToReference(sys, img, is.auths)
				if err != nil {
					return err
				}
			}

			err = sync.RegistryToImage(is.ctx, sys, srcRef, ep, copy.CopySystemImage)
			if err != nil {
				return fmt.Errorf("save image %s: %w", img, err)
			}
			outImages = append(outImages, img)
			return nil
		})
	}
	err = eg.Wait()
	errCh <- err
	return outImages, err
}
