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

package crane

import (
	"runtime"
	"strings"

	name2 "github.com/google/go-containerregistry/pkg/name"

	v1 "github.com/google/go-containerregistry/pkg/v1"

	"github.com/docker/docker/api/types/registry"
	"github.com/google/go-containerregistry/pkg/crane"

	"github.com/labring/sreg/pkg/utils/http"
)

func GetCraneOptions(authConfig map[string]registry.AuthConfig) []crane.Option {
	return []crane.Option{crane.WithAuthFromKeychain(NewDefaultKeychain(authConfig)), crane.WithTransport(http.DefaultSkipVerify)}
}

func GetImageManifestFromAuth(image string, authConfig map[string]registry.AuthConfig) (newImage string, data []byte, cfg *registry.AuthConfig, err error) {
	newImage = image
	if authConfig == nil {
		authConfig, err = GetAuthInfo(nil)
		if err != nil {
			return newImage, nil, nil, err
		}
		for domain, c := range authConfig {
			if NormalizeRegistry(domain) != domain {
				authConfig[NormalizeRegistry(domain)] = c
				delete(authConfig, domain)
			}
		}
	}
	craneOptsBase := GetCraneOptions(authConfig)
	var ref name2.Reference
	var repo string
	ref, err = name2.ParseReference(image)
	if err != nil {
		return newImage, nil, nil, err
	}
	parts := strings.SplitN(ref.Name(), "/", 2)
	if len(parts) == 2 && (strings.ContainsRune(parts[0], '.') || strings.ContainsRune(parts[0], ':')) {
		// The first part of the repository is treated as the registry domain
		// iff it contains a '.' or ':' character, otherwise it is all repository
		// and the domain defaults to Docker Hub.
		_ = parts[0]
		repo = parts[1]
	}
	craneOptsBase = append(craneOptsBase, crane.WithPlatform(&v1.Platform{
		OS:           "linux",
		Architecture: runtime.GOARCH,
	}))
	for domain, c := range authConfig {
		craneOpts := craneOptsBase[:]
		newImage = strings.Join([]string{domain, repo}, "/")
		ref, err = name2.ParseReference(newImage)
		if url, ook := http.IsURL(c.ServerAddress); ook {
			if url.Scheme == "http" {
				ref, err = name2.ParseReference(newImage, name2.Insecure)
				craneOpts = append(craneOpts, crane.Insecure)
			}
		}
		//logs.Debug.SetOutput(os.Stderr)
		if err != nil {
			continue
		}
		data, err = crane.Manifest(ref.Name(), craneOpts...)
		if err == nil {
			return newImage, data, &c, nil
		}
	}
	return image, nil, nil, err
}

func NormalizeRegistry(registry string) string {
	switch registry {
	case "registry-1.docker.io", "docker.io", "index.docker.io":
		return "index.docker.io"
	}
	return registry
}

func GetRegistryDomain(registry string) string {
	s := strings.TrimPrefix(registry, "https://")
	s = strings.TrimPrefix(s, "http://")
	return strings.Split(s, "/")[0]
}
