/*
Copyright 2023 cuisongliu@qq.com.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package http

import (
	"context"
	"github.com/labring/sreg/pkg/registry/sync"
	"testing"
)

func TestWaitUntilEndpointAlive(t *testing.T) {
	type args struct {
		ctx      context.Context
		endpoint string
	}
	tests := []struct {
		name    string
		args    args
		wantErr bool
	}{
		{
			name: "default",
			args: args{
				ctx:      context.Background(),
				endpoint: sync.ParseRegistryAddress("localhost:5050"),
			},
			wantErr: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := WaitUntilEndpointAlive(tt.args.ctx, tt.args.endpoint); (err != nil) != tt.wantErr {
				t.Errorf("WaitUntilEndpointAlive() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}
