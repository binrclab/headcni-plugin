// Copyright 2015 CNI authors
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
// like bridge or ipvlan to do the real work.

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/containernetworking/cni/pkg/invoke"
	"github.com/containernetworking/cni/pkg/skel"
	"github.com/containernetworking/cni/pkg/types"
	cni "github.com/containernetworking/cni/pkg/version"
	"gopkg.in/yaml.v3"
)

const (
	defaultSubnetFile = "/var/lib/headcni/env.yaml"
	defaultDataDir    = "/var/lib/cni/headcni"
)

var (
	Program   string = "headcni"
	Version   string = "v1.0.0"
	Commit    string = "unknown"
	buildDate string = "unknown"
)

type NetConf struct {
	types.NetConf

	// IPAM field "replaces" that of types.NetConf which is incomplete
	IPAM          map[string]interface{} `json:"ipam,omitempty"`
	SubnetFile    string                 `json:"subnetFile"`
	DataDir       string                 `json:"dataDir"`
	Delegate      map[string]interface{} `json:"delegate"`
	RuntimeConfig map[string]interface{} `json:"runtimeConfig,omitempty"`
}

type RouteConfig struct {
	Dst string `yaml:"dst"`
	Gw  string `yaml:"gw"`
}

type DNSConfig struct {
	Nameservers []string `yaml:"nameservers"`
	Search      []string `yaml:"search"`
	Options     []string `yaml:"options"`
}

type MetadataConfig struct {
	GeneratedAt string `yaml:"generated_at"`
	NodeName    string `yaml:"node_name"`
	ClusterCIDR string `yaml:"cluster_cidr"`
	ServiceCIDR string `yaml:"service_cidr"`
}

type SubnetYAML struct {
	Network     string          `yaml:"network"`
	Subnet      string          `yaml:"subnet"`
	IPv6Network string          `yaml:"ipv6_network"`
	IPv6Subnet  string          `yaml:"ipv6_subnet"`
	MTU         uint            `yaml:"mtu"`
	IPMasq      bool            `yaml:"ipmasq"`
	Metadata    *MetadataConfig `yaml:"metadata,omitempty"`
	Routes      []RouteConfig   `yaml:"routes,omitempty"`
	DNS         *DNSConfig      `yaml:"dns,omitempty"`
	Policies    interface{}     `yaml:"policies,omitempty"`
}

type subnetEnv struct {
	nws    []*net.IPNet
	sn     *net.IPNet
	ip6Nws []*net.IPNet
	ip6Sn  *net.IPNet
	mtu    *uint
	ipmasq *bool
	routes []types.Route
	dns    *DNSConfig
}

func (se *subnetEnv) missing() string {
	m := []string{}

	if len(se.nws) == 0 && len(se.ip6Nws) == 0 {
		m = append(m, []string{"network", "ipv6_network"}...)
	}
	if se.sn == nil && se.ip6Sn == nil {
		m = append(m, []string{"subnet", "ipv6_subnet"}...)
	}
	if se.mtu == nil {
		m = append(m, "mtu")
	}
	if se.ipmasq == nil {
		m = append(m, "ipmasq")
	}
	return strings.Join(m, ", ")
}

func loadHeadCNINetConf(bytes []byte) (*NetConf, error) {
	n := &NetConf{
		SubnetFile: defaultSubnetFile,
		DataDir:    defaultDataDir,
	}
	if err := json.Unmarshal(bytes, n); err != nil {
		return nil, fmt.Errorf("failed to load netconf: %v", err)
	}

	return n, nil
}

func getIPAMRoutes(n *NetConf) ([]types.Route, error) {
	rtes := []types.Route{}

	if n.IPAM != nil && hasKey(n.IPAM, "routes") {
		buf, _ := json.Marshal(n.IPAM["routes"])
		if err := json.Unmarshal(buf, &rtes); err != nil {
			return rtes, fmt.Errorf("failed to parse ipam.routes: %w", err)
		}
	}
	return rtes, nil
}

func isSubnetAlreadyPresent(nws []*net.IPNet, nw *net.IPNet) bool {
	compareMask := func(m1 net.IPMask, m2 net.IPMask) bool {
		for i := range m1 {
			if m1[i] != m2[i] {
				return false
			}
		}
		return true
	}
	for _, nwi := range nws {
		if nw.IP.Equal(nwi.IP) && compareMask(nw.Mask, nwi.Mask) {
			return true
		}
	}
	return false
}

func parseNetworks(networkStr string) ([]*net.IPNet, error) {
	if networkStr == "" {
		return []*net.IPNet{}, nil
	}

	cidrs := strings.Split(networkStr, ",")
	nws := make([]*net.IPNet, 0, len(cidrs))

	for i := range cidrs {
		cidrs[i] = strings.TrimSpace(cidrs[i])
		if cidrs[i] == "" {
			continue
		}
		_, nw, err := net.ParseCIDR(cidrs[i])
		if err != nil {
			return nil, err
		}
		if !isSubnetAlreadyPresent(nws, nw) {
			nws = append(nws, nw)
		}
	}

	return nws, nil
}

func isRouteAlreadyPresent(routes []types.Route, newRoute types.Route) bool {
	for _, r := range routes {
		if r.Dst.String() == newRoute.Dst.String() {
			// 如果目标网络相同，检查网关
			if r.GW == nil && newRoute.GW == nil {
				return true
			}
			if r.GW != nil && newRoute.GW != nil && r.GW.Equal(newRoute.GW) {
				return true
			}
		}
	}
	return false
}

func loadHeadCNISubnetYAML(fn string) (*subnetEnv, error) {
	f, err := os.Open(fn)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	data, err := io.ReadAll(f)
	if err != nil {
		return nil, err
	}

	var subnet SubnetYAML
	if err := yaml.Unmarshal(data, &subnet); err != nil {
		return nil, fmt.Errorf("failed to parse YAML: %w", err)
	}

	se := &subnetEnv{}

	// Parse IPv4 networks
	if subnet.Network != "" {
		se.nws, err = parseNetworks(subnet.Network)
		if err != nil {
			return nil, fmt.Errorf("failed to parse network: %w", err)
		}
	}

	// Parse IPv4 subnet
	if subnet.Subnet != "" {
		_, se.sn, err = net.ParseCIDR(subnet.Subnet)
		if err != nil {
			return nil, fmt.Errorf("failed to parse subnet: %w", err)
		}
	}

	// Parse IPv6 networks
	if subnet.IPv6Network != "" {
		se.ip6Nws, err = parseNetworks(subnet.IPv6Network)
		if err != nil {
			return nil, fmt.Errorf("failed to parse ipv6_network: %w", err)
		}
	}

	// Parse IPv6 subnet
	if subnet.IPv6Subnet != "" {
		_, se.ip6Sn, err = net.ParseCIDR(subnet.IPv6Subnet)
		if err != nil {
			return nil, fmt.Errorf("failed to parse ipv6_subnet: %w", err)
		}
	}

	// Set MTU
	se.mtu = &subnet.MTU

	// Set IP masquerade
	se.ipmasq = &subnet.IPMasq

	// Parse routes
	se.routes = make([]types.Route, 0, len(subnet.Routes))
	for _, route := range subnet.Routes {
		_, dst, err := net.ParseCIDR(route.Dst)
		if err != nil {
			return nil, fmt.Errorf("failed to parse route destination %s: %w", route.Dst, err)
		}

		var gw net.IP
		if route.Gw != "" {
			gw = net.ParseIP(route.Gw)
			if gw == nil {
				return nil, fmt.Errorf("failed to parse route gateway %s", route.Gw)
			}
		}

		se.routes = append(se.routes, types.Route{
			Dst: *dst,
			GW:  gw,
		})
	}

	// Set DNS
	se.dns = subnet.DNS

	if m := se.missing(); m != "" {
		return nil, fmt.Errorf("%v is missing %v", fn, m)
	}

	return se, nil
}

func saveScratchNetConf(containerID, dataDir string, netconf []byte) error {
	if err := os.MkdirAll(dataDir, 0700); err != nil {
		return err
	}
	path := filepath.Join(dataDir, containerID)
	return writeAndSyncFile(path, netconf, 0600)
}

// WriteAndSyncFile behaves just like ioutil.WriteFile in the standard library,
// but calls Sync before closing the file. WriteAndSyncFile guarantees the data
// is synced if there is no error returned.
func writeAndSyncFile(filename string, data []byte, perm os.FileMode) error {
	f, err := os.OpenFile(filename, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, perm)
	if err != nil {
		return err
	}
	n, err := f.Write(data)
	if err == nil && n < len(data) {
		err = io.ErrShortWrite
	}
	if err == nil {
		err = f.Sync()
	}
	if err1 := f.Close(); err == nil {
		err = err1
	}
	return err
}

func consumeScratchNetConf(containerID, dataDir string) (func(error), []byte, error) {
	path := filepath.Join(dataDir, containerID)

	// cleanup will do clean job when no error happens in consuming/using process
	cleanup := func(err error) {
		if err == nil {
			// Ignore errors when removing - Per spec safe to continue during DEL
			_ = os.Remove(path)
		}
	}
	netConfBytes, err := os.ReadFile(path)

	return cleanup, netConfBytes, err
}

func delegateAdd(cid, dataDir string, netconf map[string]interface{}) error {
	netconfBytes, err := json.Marshal(netconf)
	fmt.Fprintf(os.Stderr, "delegateAdd: netconf sent to delegate plugin:\n")
	os.Stderr.Write(netconfBytes)
	if err != nil {
		return fmt.Errorf("error serializing delegate netconf: %v", err)
	}

	// save the rendered netconf for cmdDel
	if err = saveScratchNetConf(cid, dataDir, netconfBytes); err != nil {
		return err
	}

	result, err := invoke.DelegateAdd(context.TODO(), netconf["type"].(string), netconfBytes, nil)
	if err != nil {
		err = fmt.Errorf("failed to delegate add: %w", err)
		return err
	}
	return result.Print()
}

func hasKey(m map[string]interface{}, k string) bool {
	_, ok := m[k]
	return ok
}

func isString(i interface{}) bool {
	_, ok := i.(string)
	return ok
}

func cmdAdd(args *skel.CmdArgs) error {
	n, err := loadHeadCNINetConf(args.StdinData)
	if err != nil {
		return fmt.Errorf("failed to load headcni netconf file: %w", err)
	}
	fenv, err := loadHeadCNISubnetYAML(n.SubnetFile)
	if err != nil {
		return fmt.Errorf("failed to load headcni 'subnet.yaml' file: %w. Check the headcni pod log for this node.", err)
	}

	if n.Delegate == nil {
		n.Delegate = make(map[string]interface{})
	} else {
		if hasKey(n.Delegate, "type") && !isString(n.Delegate["type"]) {
			return fmt.Errorf("'delegate' dictionary, if present, must have (string) 'type' field")
		}
		if hasKey(n.Delegate, "name") {
			return fmt.Errorf("'delegate' dictionary must not have 'name' field, it'll be set by headcni")
		}
		if hasKey(n.Delegate, "ipam") {
			return fmt.Errorf("'delegate' dictionary must not have 'ipam' field, it'll be set by headcni")
		}
	}

	if n.RuntimeConfig != nil {
		n.Delegate["runtimeConfig"] = n.RuntimeConfig
	}

	return doCmdAdd(args, n, fenv)
}

func cmdDel(args *skel.CmdArgs) error {
	nc, err := loadHeadCNINetConf(args.StdinData)
	if err != nil {
		return err
	}

	if nc.RuntimeConfig != nil {
		if nc.Delegate == nil {
			nc.Delegate = make(map[string]interface{})
		}
		nc.Delegate["runtimeConfig"] = nc.RuntimeConfig
	}

	return doCmdDel(args, nc)
}

func main() {
	fullVer := fmt.Sprintf("CNI Plugin %s version %s (%s/%s) commit %s built on %s", Program, Version, runtime.GOOS, runtime.GOARCH, Commit, buildDate)
	skel.PluginMain(cmdAdd, cmdCheck, cmdDel, cni.All, fullVer)
}

func cmdCheck(args *skel.CmdArgs) error {
	// TODO: implement
	return nil
}
