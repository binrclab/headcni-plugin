# HeadCNI Plugin

<div align="center">

![HeadCNI](https://img.shields.io/badge/HeadCNI-Plugin-blue?style=for-the-badge&logo=kubernetes)
![CNI](https://img.shields.io/badge/CNI-1.0.0-green?style=for-the-badge)
![Go](https://img.shields.io/badge/Go-1.21+-blue?style=for-the-badge&logo=go)
![License](https://img.shields.io/badge/License-Apache%202.0-blue?style=for-the-badge)

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen?style=flat-square)](https://github.com/binrclab/headcni-plugin)
[![Go Report Card](https://goreportcard.com/badge/github.com/binrclab/headcni-plugin)](https://goreportcard.com/report/github.com/binrclab/headcni-plugin)

**A powerful CNI meta-plugin with plugin chain execution and automatic configuration management**

[中文版本](README_CN.md)

</div>

---

## 🌟 Features

- **🔗 Plugin Chain Support** - Execute multiple CNI plugins in sequence
- **🤖 Auto IPAM Configuration** - Build IPAM configs from environment files
- **🌍 Multi-platform Support** - Linux, Windows, and macOS
- **🔄 Smart Rollback** - Automatic rollback on plugin failures
- **💾 State Management** - Save plugin states for proper cleanup
- **📝 YAML Configuration** - Human-readable environment configs

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   HeadCNI       │───▶│   Bridge        │───▶│   Portmap       │
│   Meta-Plugin   │    │   Plugin        │    │   Plugin        │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  env.yaml       │    │  Auto IPAM      │    │  Capabilities   │
│  Config         │    │  Config         │    │  Management     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🚀 Quick Start

### Installation

```bash
# Clone repository
git clone https://github.com/binrclab/headcni-plugin.git
cd headcni-plugin

# Build for your platform
make build-linux-amd64  # Linux AMD64
make build-windows-amd64  # Windows AMD64
make build-darwin-amd64   # macOS AMD64

# Or build all platforms
make build-all
```

### Basic Configuration

1. **Environment File** (`/run/headcni/env.yaml`):
```yaml
network: "10.244.0.0/16"
subnet: "10.244.0.0/24"
mtu: 1450
ipmasq: false
```

2. **CNI Config** (`/etc/cni/net.d/10-headcni.conflist`):
```json
{
  "cniVersion": "1.0.0",
  "name": "cbr0",
  "type": "headcni",
  "plugins": [
    {
      "type": "headcni",
      "delegate": {
        "hairpinMode": true,
        "isDefaultGateway": true
      }
    }
  ]
}
```

## 📖 Full Documentation

### Installation

```bash
# Clone repository
git clone https://github.com/binrclab/headcni-plugin.git
cd headcni-plugin

# Build all platforms
make build-all

# Build specific platform
make build-linux-amd64
make build-windows-amd64
make build-darwin-amd64
```

### Configuration

#### Environment File (`/run/headcni/env.yaml`)

```yaml
# Network configuration
network: "10.244.0.0/16"
subnet: "10.244.0.0/24"
ipv6_network: "fd00::/64"
ipv6_subnet: "fd00::/80"
mtu: 1450
ipmasq: false
```

#### CNI Configuration

**Plugin Chain Mode:**
```json
{
  "cniVersion": "1.0.0",
  "name": "cbr0",
  "type": "headcni",
  "plugins": [
    {
      "type": "headcni",
      "delegate": {
        "hairpinMode": true,
        "isDefaultGateway": true
      }
    },
    {
      "type": "portmap",
      "capabilities": {"portMappings": true}
    }
  ]
}
```

**Single Plugin Mode:**
```json
{
  "cniVersion": "1.0.0",
  "name": "cbr0",
  "type": "headcni",
  "delegate": {
    "type": "bridge",
    "hairpinMode": true,
    "isDefaultGateway": true
  }
}
```

### Usage

```bash
# Deploy plugin
sudo cp headcni /opt/cni/bin/
sudo chmod +x /opt/cni/bin/headcni

# Create config directories
sudo mkdir -p /etc/cni/net.d /run/headcni

# Test plugin
echo '{"cniVersion": "1.0.0", "name": "test", "type": "headcni"}' | \
sudo CNI_COMMAND=ADD CNI_CONTAINERID=test123 CNI_NETNS=/proc/1/ns/net \
CNI_IFNAME=eth0 CNI_PATH=/opt/cni/bin /opt/cni/bin/headcni
```

### Build System

```bash
# Basic build
make build                    # Build current platform
make clean                    # Clean build files

# Multi-architecture build
make build-linux-amd64       # Linux AMD64
make build-windows-amd64     # Windows AMD64
make build-darwin-amd64      # macOS AMD64

# Batch build
make build-all-linux         # All Linux architectures
make build-all               # All platform architectures
```

### Supported Architectures

- **Linux**: 386, amd64, arm, arm64, s390x, ppc64le, riscv64
- **Windows**: amd64, arm64
- **macOS**: amd64, arm64

---

<div align="center">

**Made with ❤️ by the HeadCNI Team**

[![GitHub](https://img.shields.io/badge/GitHub-100000?style=for-the-badge&logo=github&logoColor=white)](https://github.com/binrclab/headcni-plugin)
[![Issues](https://img.shields.io/badge/Issues-100000?style=for-the-badge&logo=github&logoColor=white)](https://github.com/binrclab/headcni-plugin/issues)
[![Pull Requests](https://img.shields.io/badge/Pull%20Requests-100000?style=for-the-badge&logo=github&logoColor=white)](https://github.com/binrclab/headcni-plugin/pulls)

</div>
