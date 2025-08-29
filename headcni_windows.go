//go:build windows
// +build windows

// Copyright 2025 CNI binrc
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

// This is a "meta-plugin". It reads in its own netconf, combines it with
// the data from headcni generated subnet YAML file and then invokes a plugin
// like win-bridge to do the real work.

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	"github.com/containernetworking/cni/pkg/invoke"
	"github.com/containernetworking/cni/pkg/skel"
	"github.com/containernetworking/cni/pkg/types"
	types020 "github.com/containernetworking/cni/pkg/types/020"
	"github.com/containernetworking/plugins/pkg/hns"
)

func doCmdAdd(args *skel.CmdArgs, n *NetConf, fenv *subnetEnv) error {
	n.Delegate["name"] = n.Name

	if !hasKey(n.Delegate, "type") {
		n.Delegate["type"] = "win-bridge"
	}

	// if headcni needs ipmasq - get the plugin to configure it
	// (this is the opposite of how linux works - on linux the headcni daemon configure ipmasq)
	n.Delegate["ipMasq"] = *fenv.ipmasq
	if len(fenv.nws) > 0 {
		n.Delegate["ipMasqNetwork"] = fenv.nws[0].String()
	}

	n.Delegate["cniVersion"] = types020.ImplementedSpecVersion
	if len(n.CNIVersion) != 0 {
		n.Delegate["cniVersion"] = n.CNIVersion
	}

	ipam := map[string]interface{}{
		"type":   "host-local",
		"subnet": fenv.sn.String(),
	}

	// Add routes if available
	if len(fenv.routes) > 0 {
		ipam["routes"] = fenv.routes
	}

	// Add DNS configuration if available
	if fenv.dns != nil {
		ipam["dns"] = map[string]interface{}{
			"nameservers": fenv.dns.Nameservers,
			"search":      fenv.dns.Search,
			"options":     fenv.dns.Options,
		}
	}

	n.Delegate["ipam"] = ipam

	return delegateAdd(hns.GetSandboxContainerID(args.ContainerID, args.Netns), n.DataDir, n.Delegate)
}

func doCmdDel(args *skel.CmdArgs, n *NetConf) (err error) {
	cleanup, netConfBytes, err := consumeScratchNetConf(hns.GetSandboxContainerID(args.ContainerID, args.Netns), n.DataDir)
	if err != nil {
		if os.IsNotExist(err) {
			// Per spec should ignore error if resources are missing / already removed
			return nil
		}
		return err
	}

	// cleanup will work when no error happens
	defer func() {
		cleanup(err)
	}()

	nc := &types.NetConf{}
	if err = json.Unmarshal(netConfBytes, nc); err != nil {
		return fmt.Errorf("failed to parse netconf: %v", err)
	}

	return invoke.DelegateDel(context.TODO(), nc.Type, netConfBytes, nil)
}
