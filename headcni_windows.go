// headcni_windows.go
//go:build windows
// +build windows

package main

import "github.com/containernetworking/plugins/pkg/hns"

type WindowsAdapterWithHNS struct {
	WindowsAdapter
}

func (a *WindowsAdapterWithHNS) GetRealContainerID(containerID, netns string) string {
	return hns.GetSandboxContainerID(containerID, netns)
}

func init() {
	platform = &WindowsAdapterWithHNS{}
}
