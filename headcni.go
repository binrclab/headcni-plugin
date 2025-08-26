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

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/containernetworking/cni/pkg/invoke"
	"github.com/containernetworking/cni/pkg/skel"
	"github.com/containernetworking/cni/pkg/types"
	cnitypes "github.com/containernetworking/cni/pkg/types/100"
	cni "github.com/containernetworking/cni/pkg/version"
	"gopkg.in/yaml.v3"
)

const (
	defaultSubnetFile = "/run/headcni/env.yaml"
	defaultDataDir    = "/var/lib/cni/headcni"
	maxPluginRetries  = 3
)

var (
	Program   string = "headcni"
	Version   string
	Commit    string
	buildDate string
)

// ========================= Core Types =========================

// NetConf defines the configuration structure for headcni
type NetConf struct {
	types.NetConf

	IPAM          map[string]interface{}   `json:"ipam,omitempty"`
	SubnetFile    string                   `json:"subnetFile"`
	DataDir       string                   `json:"dataDir"`
	Delegate      map[string]interface{}   `json:"delegate,omitempty"`
	Plugins       []map[string]interface{} `json:"plugins,omitempty"`
	RuntimeConfig map[string]interface{}   `json:"runtimeConfig,omitempty"`
}

// SubnetEnvironment holds network environment configuration
type SubnetEnvironment struct {
	IPv4Networks []*net.IPNet
	IPv4Subnet   *net.IPNet
	IPv6Networks []*net.IPNet
	IPv6Subnet   *net.IPNet
	MTU          *uint
	IPMasq       *bool
}

// PluginState represents the state of a plugin in the execution chain
type PluginState struct {
	Index      int                    `json:"index"`
	Type       string                 `json:"type"`
	Config     map[string]interface{} `json:"config"`
	ExecutedAt int64                  `json:"executed_at"`
}

// ========================= Platform Abstraction =========================

// PlatformAdapter abstracts platform-specific behaviors
type PlatformAdapter interface {
	GetContainerID(containerID, netns string) string
	GetDefaults() (subnetFile, dataDir string)
	GetDefaultPluginType() string
	ConfigureDelegate(delegate map[string]interface{}, n *NetConf, env *SubnetEnvironment)
}

// LinuxAdapter implements Linux-specific behavior
type LinuxAdapter struct{}

func (a *LinuxAdapter) GetContainerID(containerID, netns string) string {
	return containerID
}

func (a *LinuxAdapter) GetDefaults() (string, string) {
	return defaultSubnetFile, defaultDataDir
}

func (a *LinuxAdapter) GetDefaultPluginType() string {
	return "bridge"
}

func (a *LinuxAdapter) ConfigureDelegate(delegate map[string]interface{}, n *NetConf, env *SubnetEnvironment) {
	// Linux bridge plugin uses inverted ipMasq logic
	if !hasKey(delegate, "ipMasq") && env.IPMasq != nil {
		delegate["ipMasq"] = !*env.IPMasq
	}

	// Bridge-specific configuration
	if pluginType, ok := delegate["type"].(string); ok && pluginType == "bridge" {
		if !hasKey(delegate, "isGateway") {
			delegate["isGateway"] = true
		}
		if !hasKey(delegate, "bridge") {
			delegate["bridge"] = n.Name
		}
	}
}

// WindowsAdapter implements Windows-specific behavior
type WindowsAdapter struct{}

func (a *WindowsAdapter) GetContainerID(containerID, netns string) string {
	// Would use HNS package in actual Windows build
	return containerID
}

func (a *WindowsAdapter) GetDefaults() (string, string) {
	return "", "" // Windows requires explicit paths
}

func (a *WindowsAdapter) GetDefaultPluginType() string {
	return "win-bridge"
}

func (a *WindowsAdapter) ConfigureDelegate(delegate map[string]interface{}, n *NetConf, env *SubnetEnvironment) {
	// Windows uses direct ipMasq boolean
	if env.IPMasq != nil {
		delegate["ipMasq"] = *env.IPMasq
	}

	// Set masquerading network
	if len(env.IPv4Networks) > 0 {
		delegate["ipMasqNetwork"] = env.IPv4Networks[0].String()
	}
}

var platform PlatformAdapter = &LinuxAdapter{}

// ========================= Plugin Chain Executor =========================

// PluginChainExecutor manages plugin chain execution with state persistence
type PluginChainExecutor struct {
	dataDir string
	mu      sync.RWMutex
}

// NewPluginChainExecutor creates a new executor instance
func NewPluginChainExecutor(dataDir string) *PluginChainExecutor {
	return &PluginChainExecutor{dataDir: dataDir}
}

// ExecuteChain executes the complete plugin chain
func (pce *PluginChainExecutor) ExecuteChain(args *skel.CmdArgs, n *NetConf, env *SubnetEnvironment) error {
	if len(n.Plugins) == 0 {
		return pce.executeSingleDelegate(args, n, env)
	}

	fmt.Fprintf(os.Stderr, "Executing plugin chain with %d plugins\n", len(n.Plugins))

	var currentResult types.Result
	realContainerID := platform.GetContainerID(args.ContainerID, args.Netns)

	for i, pluginConf := range n.Plugins {
		plugin := pce.preparePluginConfig(pluginConf, n)

		pluginType, ok := plugin["type"].(string)
		if !ok {
			pce.rollback(args.ContainerID, i, n.Plugins)
			return fmt.Errorf("plugin %d missing type field", i)
		}

		fmt.Fprintf(os.Stderr, "Executing plugin %d: %s\n", i, pluginType)

		result, err := pce.executePlugin(args, plugin, currentResult, n, env)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Plugin %d (%s) failed: %v\n", i, pluginType, err)
			pce.rollback(args.ContainerID, i, n.Plugins)
			return fmt.Errorf("plugin %d (%s) failed: %w", i, pluginType, err)
		}

		if err = pce.savePluginState(realContainerID, i, plugin); err != nil {
			pce.rollback(args.ContainerID, i+1, n.Plugins)
			return fmt.Errorf("failed to save plugin %d state: %w", i, err)
		}

		currentResult = result
		fmt.Fprintf(os.Stderr, "Plugin %d (%s) executed successfully\n", i, pluginType)
	}

	if currentResult != nil {
		return currentResult.Print()
	}
	return nil
}

// DeleteChain deletes the plugin chain in reverse order
func (pce *PluginChainExecutor) DeleteChain(args *skel.CmdArgs, n *NetConf) error {
	realContainerID := platform.GetContainerID(args.ContainerID, args.Netns)

	states, err := pce.loadPluginStates(realContainerID)
	if err != nil || len(states) == 0 {
		fmt.Fprintf(os.Stderr, "No plugin states found, attempting single delegate deletion\n")
		return pce.deleteSingleDelegate(args, n)
	}

	fmt.Fprintf(os.Stderr, "Found %d plugin states, deleting in reverse order\n", len(states))

	var lastErr error
	for i := len(states) - 1; i >= 0; i-- {
		state := states[i]
		if err := pce.deletePluginByState(state, realContainerID); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: failed to delete plugin %d (%s): %v\n",
				state.Index, state.Type, err)
			lastErr = err
		}
	}

	return lastErr
}

// ========================= Private Methods =========================

func (pce *PluginChainExecutor) preparePluginConfig(pluginConf map[string]interface{}, n *NetConf) map[string]interface{} {
	plugin := make(map[string]interface{}, len(pluginConf)+4)
	for k, v := range pluginConf {
		plugin[k] = v
	}

	plugin["name"] = n.Name
	if n.CNIVersion != "" {
		plugin["cniVersion"] = n.CNIVersion
	}
	if n.RuntimeConfig != nil {
		plugin["runtimeConfig"] = n.RuntimeConfig
	}

	return plugin
}

func (pce *PluginChainExecutor) executePlugin(args *skel.CmdArgs, plugin map[string]interface{},
	prevResult types.Result, n *NetConf, env *SubnetEnvironment) (types.Result, error) {

	if prevResult != nil {
		plugin["prevResult"] = prevResult
	}

	if pce.isHeadcniPlugin(plugin) {
		return pce.executeHeadcniPlugin(args, plugin, n, env)
	}

	return pce.executeRegularPlugin(plugin)
}

func (pce *PluginChainExecutor) executeHeadcniPlugin(args *skel.CmdArgs, plugin map[string]interface{},
	n *NetConf, env *SubnetEnvironment) (types.Result, error) {

	delegateConf, _ := plugin["delegate"].(map[string]interface{})
	if delegateConf == nil {
		delegateConf = make(map[string]interface{})
	}

	delegate := pce.buildDelegateConfig(delegateConf, n, env)

	delegateBytes, err := json.Marshal(delegate)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal delegate config: %w", err)
	}

	realContainerID := platform.GetContainerID(args.ContainerID, args.Netns)
	if err = pce.saveDelegateConfig(realContainerID, delegateBytes); err != nil {
		return nil, fmt.Errorf("failed to save delegate config: %w", err)
	}

	delegateType := delegate["type"].(string)
	fmt.Fprintf(os.Stderr, "Headcni delegating to %s\n", delegateType)

	result, err := invoke.DelegateAdd(context.TODO(), delegateType, delegateBytes, nil)
	if err != nil {
		return nil, fmt.Errorf("headcni delegate to %s failed: %w", delegateType, err)
	}

	return pce.enhanceResult(result, env)
}

func (pce *PluginChainExecutor) executeRegularPlugin(plugin map[string]interface{}) (types.Result, error) {
	pluginType := plugin["type"].(string)

	pluginBytes, err := json.Marshal(plugin)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal plugin config: %w", err)
	}

	var result types.Result
	for attempt := 1; attempt <= maxPluginRetries; attempt++ {
		result, err = invoke.DelegateAdd(context.TODO(), pluginType, pluginBytes, nil)
		if err == nil {
			break
		}

		if attempt < maxPluginRetries {
			fmt.Fprintf(os.Stderr, "Plugin %s failed (attempt %d/%d), retrying...\n",
				pluginType, attempt, maxPluginRetries)
		}
	}

	if err != nil {
		return nil, fmt.Errorf("plugin %s failed after %d attempts: %w", pluginType, maxPluginRetries, err)
	}

	return result, nil
}

func (pce *PluginChainExecutor) buildDelegateConfig(delegateConf map[string]interface{},
	n *NetConf, env *SubnetEnvironment) map[string]interface{} {

	delegate := make(map[string]interface{}, len(delegateConf)+8)
	for k, v := range delegateConf {
		delegate[k] = v
	}

	// Set CNI fields
	delegate["name"] = n.Name
	if n.CNIVersion != "" {
		delegate["cniVersion"] = n.CNIVersion
	}

	// Set default plugin type
	if !hasKey(delegate, "type") {
		delegate["type"] = platform.GetDefaultPluginType()
	}

	// Configure IPAM
	if !hasKey(delegate, "ipam") {
		delegate["ipam"] = pce.buildIPAMConfig(env)
	}

	// Set MTU
	if env.MTU != nil && !hasKey(delegate, "mtu") {
		delegate["mtu"] = *env.MTU
	}

	// Apply platform-specific configuration
	platform.ConfigureDelegate(delegate, n, env)

	// Add runtime config
	if n.RuntimeConfig != nil {
		delegate["runtimeConfig"] = n.RuntimeConfig
	}

	return delegate
}

func (pce *PluginChainExecutor) buildIPAMConfig(env *SubnetEnvironment) map[string]interface{} {
	ipam := map[string]interface{}{
		"type":    "host-local",
		"dataDir": filepath.Join(pce.dataDir, "ipam"),
	}

	var ranges [][]map[string]interface{}

	if env.IPv4Subnet != nil {
		rangeConfig := map[string]interface{}{
			"subnet": env.IPv4Subnet.String(),
		}
		if gw := getFirstUsableIP(env.IPv4Subnet); gw != nil {
			rangeConfig["gateway"] = gw.String()
		}
		ranges = append(ranges, []map[string]interface{}{rangeConfig})
	}

	if env.IPv6Subnet != nil {
		rangeConfig := map[string]interface{}{
			"subnet": env.IPv6Subnet.String(),
		}
		if gw := getFirstUsableIPv6(env.IPv6Subnet); gw != nil {
			rangeConfig["gateway"] = gw.String()
		}
		ranges = append(ranges, []map[string]interface{}{rangeConfig})
	}

	if len(ranges) > 0 {
		ipam["ranges"] = ranges
	}

	// Build routes
	var routes []map[string]interface{}
	for _, nw := range env.IPv4Networks {
		if nw != nil {
			routes = append(routes, map[string]interface{}{"dst": nw.String()})
		}
	}
	for _, nw := range env.IPv6Networks {
		if nw != nil {
			routes = append(routes, map[string]interface{}{"dst": nw.String()})
		}
	}

	if len(routes) > 0 {
		ipam["routes"] = routes
	}

	return ipam
}

func (pce *PluginChainExecutor) enhanceResult(result types.Result, env *SubnetEnvironment) (types.Result, error) {
	cniResult, err := cnitypes.NewResultFromResult(result)
	if err != nil {
		return nil, fmt.Errorf("failed to convert result to CNI 1.0: %w", err)
	}

	existingRoutes := make(map[string]bool)
	for _, route := range cniResult.Routes {
		if route != nil {
			existingRoutes[route.Dst.String()] = true
		}
	}

	// Add missing routes
	for _, nw := range env.IPv4Networks {
		if nw != nil && !existingRoutes[nw.String()] {
			cniResult.Routes = append(cniResult.Routes, &types.Route{Dst: *nw})
		}
	}

	for _, nw := range env.IPv6Networks {
		if nw != nil && !existingRoutes[nw.String()] {
			cniResult.Routes = append(cniResult.Routes, &types.Route{Dst: *nw})
		}
	}

	return cniResult, nil
}

// ========================= State Management =========================

func (pce *PluginChainExecutor) savePluginState(containerID string, index int, plugin map[string]interface{}) error {
	pce.mu.Lock()
	defer pce.mu.Unlock()

	pluginType, _ := plugin["type"].(string)
	state := &PluginState{
		Index:      index,
		Type:       pluginType,
		Config:     plugin,
		ExecutedAt: time.Now().Unix(),
	}

	stateBytes, err := json.Marshal(state)
	if err != nil {
		return fmt.Errorf("failed to marshal plugin state: %w", err)
	}

	filename := fmt.Sprintf("%s-plugin-%d", containerID, index)
	path := filepath.Join(pce.dataDir, filename)

	return writeFileAtomically(path, stateBytes, 0600)
}

func (pce *PluginChainExecutor) loadPluginStates(containerID string) ([]*PluginState, error) {
	pce.mu.RLock()
	defer pce.mu.RUnlock()

	var states []*PluginState
	for i := 0; ; i++ {
		filename := fmt.Sprintf("%s-plugin-%d", containerID, i)
		path := filepath.Join(pce.dataDir, filename)

		data, err := os.ReadFile(path)
		if os.IsNotExist(err) {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("failed to read plugin state file %s: %w", path, err)
		}

		var state PluginState
		if err := json.Unmarshal(data, &state); err != nil {
			return nil, fmt.Errorf("failed to unmarshal plugin state: %w", err)
		}

		states = append(states, &state)
	}

	return states, nil
}

func (pce *PluginChainExecutor) saveDelegateConfig(containerID string, config []byte) error {
	pce.mu.Lock()
	defer pce.mu.Unlock()

	if err := os.MkdirAll(pce.dataDir, 0700); err != nil {
		return fmt.Errorf("failed to create data directory: %w", err)
	}

	path := filepath.Join(pce.dataDir, containerID+"-delegate")
	return writeFileAtomically(path, config, 0600)
}

func (pce *PluginChainExecutor) loadDelegateConfig(containerID string) ([]byte, error) {
	pce.mu.RLock()
	defer pce.mu.RUnlock()

	path := filepath.Join(pce.dataDir, containerID+"-delegate")
	return os.ReadFile(path)
}

// ========================= Configuration Loading =========================

func loadNetworkConfig(bytes []byte) (*NetConf, error) {
	var subnetFile, dataDir string

	if envFile := strings.TrimSpace(os.Getenv("HEADCNI_SUBNET_FILE")); envFile != "" {
		subnetFile = envFile
	}
	if envDir := strings.TrimSpace(os.Getenv("HEADCNI_DATA_DIR")); envDir != "" {
		dataDir = envDir
	}

	if subnetFile == "" || dataDir == "" {
		defaultSubnet, defaultData := platform.GetDefaults()
		if subnetFile == "" {
			subnetFile = defaultSubnet
		}
		if dataDir == "" {
			dataDir = defaultData
		}
	}

	if subnetFile == "" || dataDir == "" {
		return nil, fmt.Errorf("HEADCNI_SUBNET_FILE and HEADCNI_DATA_DIR must be set")
	}

	n := &NetConf{SubnetFile: subnetFile, DataDir: dataDir}
	if err := json.Unmarshal(bytes, n); err != nil {
		return nil, fmt.Errorf("failed to load netconf: %w", err)
	}

	return n, validateNetConf(n)
}

func loadSubnetEnvironment(filename string) (*SubnetEnvironment, error) {
	data, err := os.ReadFile(filename)
	if err != nil {
		return nil, fmt.Errorf("failed to read subnet file %s: %w", filename, err)
	}

	var yamlData map[string]interface{}
	if err := yaml.Unmarshal(data, &yamlData); err != nil {
		return nil, fmt.Errorf("failed to parse YAML: %w", err)
	}

	env := &SubnetEnvironment{}
	if err := parseEnvironmentData(yamlData, env); err != nil {
		return nil, err
	}

	if missing := env.getMissingFields(); missing != "" {
		return nil, fmt.Errorf("missing required fields: %s", missing)
	}

	return env, nil
}

func parseEnvironmentData(data map[string]interface{}, env *SubnetEnvironment) error {
	// Parse IPv4 network
	if networkStr, ok := getStringValue(data, "network"); ok {
		networks, err := parseNetworkCIDRs(networkStr)
		if err != nil {
			return fmt.Errorf("invalid network configuration: %w", err)
		}
		env.IPv4Networks = networks
	}

	// Parse IPv4 subnet
	if subnetStr, ok := getStringValue(data, "subnet"); ok {
		_, subnet, err := net.ParseCIDR(strings.TrimSpace(subnetStr))
		if err != nil {
			return fmt.Errorf("invalid subnet CIDR: %w", err)
		}
		env.IPv4Subnet = subnet
	}

	// Parse IPv6 network
	if networkStr, ok := getStringValue(data, "ipv6_network"); ok {
		networks, err := parseNetworkCIDRs(networkStr)
		if err != nil {
			return fmt.Errorf("invalid IPv6 network configuration: %w", err)
		}
		env.IPv6Networks = networks
	}

	// Parse IPv6 subnet
	if subnetStr, ok := getStringValue(data, "ipv6_subnet"); ok {
		_, subnet, err := net.ParseCIDR(strings.TrimSpace(subnetStr))
		if err != nil {
			return fmt.Errorf("invalid IPv6 subnet CIDR: %w", err)
		}
		env.IPv6Subnet = subnet
	}

	// Parse MTU
	if mtuData, ok := data["mtu"]; ok {
		mtu, err := parseUintValue(mtuData)
		if err != nil {
			return fmt.Errorf("invalid MTU: %w", err)
		}
		env.MTU = &mtu
	}

	// Parse IP masquerade setting
	if ipmasqData, ok := data["ipmasq"]; ok {
		ipmasq, err := parseBoolValue(ipmasqData)
		if err != nil {
			return fmt.Errorf("invalid ipmasq: %w", err)
		}
		env.IPMasq = &ipmasq
	}

	return nil
}

// ========================= Helper Functions =========================

func (env *SubnetEnvironment) getMissingFields() string {
	var missing []string
	if len(env.IPv4Networks) == 0 && len(env.IPv6Networks) == 0 {
		missing = append(missing, "network/ipv6_network")
	}
	if env.IPv4Subnet == nil && env.IPv6Subnet == nil {
		missing = append(missing, "subnet/ipv6_subnet")
	}
	if env.MTU == nil {
		missing = append(missing, "mtu")
	}
	if env.IPMasq == nil {
		missing = append(missing, "ipmasq")
	}
	return strings.Join(missing, ", ")
}

func validateNetConf(n *NetConf) error {
	if n.Name == "" {
		return fmt.Errorf("network name is required")
	}
	if len(n.Plugins) > 0 && n.Delegate != nil {
		return fmt.Errorf("cannot specify both 'plugins' and 'delegate' fields")
	}
	for i, plugin := range n.Plugins {
		if pluginType, ok := plugin["type"].(string); !ok || pluginType == "" {
			return fmt.Errorf("plugin %d missing type field", i)
		}
	}
	return nil
}

func parseNetworkCIDRs(cidrsStr string) ([]*net.IPNet, error) {
	cidrs := strings.Split(cidrsStr, ",")
	networks := make([]*net.IPNet, 0, len(cidrs))

	for _, cidr := range cidrs {
		cidr = strings.TrimSpace(cidr)
		if cidr == "" {
			continue
		}

		_, network, err := net.ParseCIDR(cidr)
		if err != nil {
			return nil, fmt.Errorf("invalid CIDR %s: %w", cidr, err)
		}

		if !containsNetwork(networks, network) {
			networks = append(networks, network)
		}
	}

	return networks, nil
}

func getStringValue(data map[string]interface{}, key string) (string, bool) {
	if val, ok := data[key]; ok {
		if str, ok := val.(string); ok {
			return str, true
		}
	}
	return "", false
}

func parseUintValue(value interface{}) (uint, error) {
	switch v := value.(type) {
	case int:
		if v < 0 {
			return 0, fmt.Errorf("value must be non-negative")
		}
		return uint(v), nil
	case string:
		parsed, err := strconv.ParseUint(v, 10, 32)
		if err != nil {
			return 0, err
		}
		return uint(parsed), nil
	default:
		return 0, fmt.Errorf("expected int or string, got %T", v)
	}
}

func parseBoolValue(value interface{}) (bool, error) {
	switch v := value.(type) {
	case bool:
		return v, nil
	case string:
		return strings.ToLower(v) == "true", nil
	default:
		return false, fmt.Errorf("expected bool or string, got %T", v)
	}
}

func containsNetwork(networks []*net.IPNet, target *net.IPNet) bool {
	for _, existing := range networks {
		if existing.IP.Equal(target.IP) && existing.Mask.String() == target.Mask.String() {
			return true
		}
	}
	return false
}

func getFirstUsableIP(subnet *net.IPNet) net.IP {
	if subnet == nil {
		return nil
	}

	ip := make(net.IP, len(subnet.IP))
	copy(ip, subnet.IP)

	// Increment by 1 to skip network address
	for i := len(ip) - 1; i >= 0; i-- {
		ip[i]++
		if ip[i] > 0 {
			break
		}
	}

	if subnet.Contains(ip) {
		return ip
	}
	return nil
}

func getFirstUsableIPv6(subnet *net.IPNet) net.IP {
	if subnet == nil || subnet.IP.To4() != nil {
		return nil
	}

	ip := make(net.IP, len(subnet.IP))
	copy(ip, subnet.IP)

	for i := len(ip) - 1; i >= 0; i-- {
		ip[i]++
		if ip[i] > 0 {
			break
		}
	}

	if subnet.Contains(ip) {
		return ip
	}
	return nil
}

func writeFileAtomically(filename string, data []byte, perm os.FileMode) error {
	dir := filepath.Dir(filename)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create directory: %w", err)
	}

	tmpFile := filename + ".tmp"
	f, err := os.OpenFile(tmpFile, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, perm)
	if err != nil {
		return err
	}

	defer func() {
		f.Close()
		os.Remove(tmpFile)
	}()

	if _, err := f.Write(data); err != nil {
		return err
	}

	if err := f.Sync(); err != nil {
		return err
	}

	if err := f.Close(); err != nil {
		return err
	}

	return os.Rename(tmpFile, filename)
}

func hasKey(m map[string]interface{}, k string) bool {
	_, ok := m[k]
	return ok
}

// ========================= Cleanup and Rollback =========================

func (pce *PluginChainExecutor) rollback(containerID string, failedIndex int, plugins []map[string]interface{}) {
	fmt.Fprintf(os.Stderr, "Rolling back plugins due to failure at index %d\n", failedIndex)

	for i := failedIndex - 1; i >= 0; i-- {
		plugin := plugins[i]
		pluginType, _ := plugin["type"].(string)

		if i == 0 && pce.isHeadcniPlugin(plugin) {
			realContainerID := platform.GetContainerID(containerID, "")
			if err := pce.deleteHeadcniPlugin(realContainerID); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: failed to rollback headcni plugin: %v\n", err)
			}
		} else {
			pluginBytes, err := json.Marshal(plugin)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Warning: failed to marshal plugin for rollback: %v\n", err)
				continue
			}

			if err := invoke.DelegateDel(context.TODO(), pluginType, pluginBytes, nil); err != nil {
				fmt.Fprintf(os.Stderr, "Warning: failed to rollback plugin %s: %v\n", pluginType, err)
			}
		}

		if err := pce.cleanupPluginState(containerID, i); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: failed to cleanup plugin state: %v\n", err)
		}
	}
}

func (pce *PluginChainExecutor) deletePluginByState(state *PluginState, containerID string) error {
	fmt.Fprintf(os.Stderr, "Deleting plugin %d: %s\n", state.Index, state.Type)

	var err error
	if state.Index == 0 && (state.Type == "headcni" || pce.isHeadcniPlugin(state.Config)) {
		err = pce.deleteHeadcniPlugin(containerID)
	} else {
		pluginBytes, marshalErr := json.Marshal(state.Config)
		if marshalErr != nil {
			return fmt.Errorf("failed to marshal plugin config: %w", marshalErr)
		}
		err = invoke.DelegateDel(context.TODO(), state.Type, pluginBytes, nil)
	}

	// Always cleanup state file
	if cleanupErr := pce.cleanupPluginState(containerID, state.Index); cleanupErr != nil {
		fmt.Fprintf(os.Stderr, "Warning: failed to cleanup plugin state: %v\n", cleanupErr)
	}

	return err
}

func (pce *PluginChainExecutor) deleteHeadcniPlugin(containerID string) error {
	delegateBytes, err := pce.loadDelegateConfig(containerID)
	if err != nil {
		return fmt.Errorf("failed to load delegate config: %w", err)
	}

	var delegate map[string]interface{}
	if err := json.Unmarshal(delegateBytes, &delegate); err != nil {
		return fmt.Errorf("failed to parse delegate config: %w", err)
	}

	delegateType, ok := delegate["type"].(string)
	if !ok {
		return fmt.Errorf("delegate config missing type field")
	}

	fmt.Fprintf(os.Stderr, "Deleting headcni delegate plugin: %s\n", delegateType)
	err = invoke.DelegateDel(context.TODO(), delegateType, delegateBytes, nil)

	// Cleanup delegate config file
	delegatePath := filepath.Join(pce.dataDir, containerID+"-delegate")
	if removeErr := os.Remove(delegatePath); removeErr != nil && !os.IsNotExist(removeErr) {
		fmt.Fprintf(os.Stderr, "Warning: failed to remove delegate config: %v\n", removeErr)
	}

	return err
}

func (pce *PluginChainExecutor) cleanupPluginState(containerID string, index int) error {
	pce.mu.Lock()
	defer pce.mu.Unlock()

	filename := fmt.Sprintf("%s-plugin-%d", containerID, index)
	path := filepath.Join(pce.dataDir, filename)

	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to remove plugin state file: %w", err)
	}
	return nil
}

func (pce *PluginChainExecutor) isHeadcniPlugin(plugin map[string]interface{}) bool {
	if pluginType, ok := plugin["type"].(string); ok && pluginType == "headcni" {
		return true
	}
	_, hasDelegate := plugin["delegate"]
	return hasDelegate
}

func (pce *PluginChainExecutor) executeSingleDelegate(args *skel.CmdArgs, n *NetConf, env *SubnetEnvironment) error {
	if n.Delegate == nil {
		n.Delegate = make(map[string]interface{})
	}

	delegate := pce.buildDelegateConfig(n.Delegate, n, env)

	delegateBytes, err := json.Marshal(delegate)
	if err != nil {
		return fmt.Errorf("failed to marshal delegate config: %w", err)
	}

	realContainerID := platform.GetContainerID(args.ContainerID, args.Netns)
	if err = pce.saveDelegateConfig(realContainerID, delegateBytes); err != nil {
		return fmt.Errorf("failed to save delegate config: %w", err)
	}

	delegateType, ok := delegate["type"].(string)
	if !ok {
		return fmt.Errorf("delegate config missing type field")
	}

	fmt.Fprintf(os.Stderr, "delegateAdd: executing %s\n", delegateType)

	result, err := invoke.DelegateAdd(context.TODO(), delegateType, delegateBytes, nil)
	if err != nil {
		return fmt.Errorf("delegateAdd to %s failed: %w", delegateType, err)
	}

	enhancedResult, err := pce.enhanceResult(result, env)
	if err != nil {
		return fmt.Errorf("failed to enhance result: %w", err)
	}

	return enhancedResult.Print()
}

func (pce *PluginChainExecutor) deleteSingleDelegate(args *skel.CmdArgs, n *NetConf) error {
	realContainerID := platform.GetContainerID(args.ContainerID, args.Netns)

	delegateBytes, err := pce.loadDelegateConfig(realContainerID)
	if err != nil {
		if os.IsNotExist(err) {
			fmt.Fprintf(os.Stderr, "Warning: no delegate config found for container %s\n", args.ContainerID)
			return nil
		}
		return fmt.Errorf("failed to load delegate config: %w", err)
	}

	var delegate map[string]interface{}
	if err := json.Unmarshal(delegateBytes, &delegate); err != nil {
		return fmt.Errorf("failed to parse delegate config: %w", err)
	}

	delegateType, ok := delegate["type"].(string)
	if !ok {
		return fmt.Errorf("delegate config missing type field")
	}

	fmt.Fprintf(os.Stderr, "Deleting single delegate plugin: %s\n", delegateType)

	err = invoke.DelegateDel(context.TODO(), delegateType, delegateBytes, nil)

	// Cleanup config file
	delegatePath := filepath.Join(pce.dataDir, args.ContainerID+"-delegate")
	if removeErr := os.Remove(delegatePath); removeErr != nil && !os.IsNotExist(removeErr) {
		fmt.Fprintf(os.Stderr, "Warning: failed to remove delegate config: %v\n", removeErr)
	}

	return err
}

// ========================= Main Command Handlers =========================

func cmdAdd(args *skel.CmdArgs) error {
	n, err := loadNetworkConfig(args.StdinData)
	if err != nil {
		return fmt.Errorf("failed to load network config: %w", err)
	}

	env, err := loadSubnetEnvironment(n.SubnetFile)
	if err != nil {
		return fmt.Errorf("failed to load subnet environment: %w", err)
	}

	executor := NewPluginChainExecutor(n.DataDir)
	return executor.ExecuteChain(args, n, env)
}

func cmdDel(args *skel.CmdArgs) error {
	n, err := loadNetworkConfig(args.StdinData)
	if err != nil {
		return fmt.Errorf("failed to load network config: %w", err)
	}

	// Merge runtime config if present
	if n.RuntimeConfig != nil {
		if n.Delegate == nil {
			n.Delegate = make(map[string]interface{})
		}
		n.Delegate["runtimeConfig"] = n.RuntimeConfig
	}

	executor := NewPluginChainExecutor(n.DataDir)
	return executor.DeleteChain(args, n)
}

func cmdCheck(args *skel.CmdArgs) error {
	n, err := loadNetworkConfig(args.StdinData)
	if err != nil {
		return fmt.Errorf("failed to load network config: %w", err)
	}

	if _, err := os.Stat(n.SubnetFile); os.IsNotExist(err) {
		return fmt.Errorf("subnet file %s does not exist", n.SubnetFile)
	}

	_, err = loadSubnetEnvironment(n.SubnetFile)
	if err != nil {
		return fmt.Errorf("failed to validate subnet file: %w", err)
	}

	fmt.Fprintf(os.Stderr, "Configuration check passed\n")
	return nil
}

func main() {
	version := fmt.Sprintf("CNI Plugin %s version %s (%s/%s) commit %s built on %s",
		Program, Version, runtime.GOOS, runtime.GOARCH, Commit, buildDate)
	skel.PluginMain(cmdAdd, cmdCheck, cmdDel, cni.All, version)
}
