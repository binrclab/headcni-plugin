# HeadCNI 插件

<div align="center">

![HeadCNI](https://img.shields.io/badge/HeadCNI-Plugin-blue?style=for-the-badge&logo=kubernetes)
![CNI](https://img.shields.io/badge/CNI-1.0.0-green?style=for-the-badge)
![Go](https://img.shields.io/badge/Go-1.21+-blue?style=for-the-badge&logo=go)
![License](https://img.shields.io/badge/License-Apache%202.0-blue?style=for-the-badge)

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen?style=flat-square)](https://github.com/binrclab/headcni-plugin)
[![Go Report Card](https://goreportcard.com/badge/github.com/binrclab/headcni-plugin)](https://goreportcard.com/report/github.com/binrclab/headcni-plugin)

**一个强大的CNI元插件，支持插件链执行和自动配置管理**

[English Version](README.md)

</div>

---

## 🌟 特性

- **🔗 插件链支持** - 按顺序执行多个CNI插件
- **🤖 自动IPAM配置** - 从环境文件自动构建IPAM配置
- **🌍 多平台支持** - 支持Linux、Windows和macOS
- **🔄 智能回滚** - 插件失败时自动回滚
- **💾 状态管理** - 保存插件状态以便正确清理
- **📝 YAML配置** - 人类可读的环境配置文件

## 🏗️ 架构

```
┌─────────────────┐     ┌─────────────────┐    ┌─────────────────┐
│   HeadCNI       │───▶│   Bridge        │───▶│   Portmap       │
│   元插件        │     │   插件          │     │   插件          │
└─────────────────┘     └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  env.yaml       │    │  自动IPAM       │    │  能力管理       │
│  配置文件        │    │  配置           │    │                │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🚀 快速开始

### 安装

```bash
# 克隆仓库
git clone https://github.com/binrclab/headcni-plugin.git
cd headcni-plugin

# 为你的平台编译
make build-linux-amd64  # Linux AMD64
make build-windows-amd64  # Windows AMD64
make build-darwin-amd64   # macOS AMD64

# 或编译所有平台
make build-all
```

### 基本配置

1. **环境文件** (`/run/headcni/env.yaml`):
```yaml
network: "10.244.0.0/16"
subnet: "10.244.0.0/24"
mtu: 1450
ipmasq: false
```

2. **CNI配置** (`/etc/cni/net.d/10-headcni.conflist`):
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

## 📖 完整文档

### 安装

```bash
# 克隆仓库
git clone https://github.com/binrclab/headcni-plugin.git
cd headcni-plugin

# 编译所有平台
make build-all

# 编译特定平台
make build-linux-amd64
make build-windows-amd64
make build-darwin-amd64
```

### 配置

#### 环境配置文件 (`/run/headcni/env.yaml`)

```yaml
# 网络配置
network: "10.244.0.0/16"
subnet: "10.244.0.0/24"
ipv6_network: "fd00::/64"
ipv6_subnet: "fd00::/80"
mtu: 1450
ipmasq: false
```

#### CNI配置文件

**插件链模式:**
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

**单插件模式:**
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

### 使用方法

```bash
# 部署插件
sudo cp headcni /opt/cni/bin/
sudo chmod +x /opt/cni/bin/headcni

# 创建配置目录
sudo mkdir -p /etc/cni/net.d /run/headcni

# 测试插件
echo '{"cniVersion": "1.0.0", "name": "test", "type": "headcni"}' | \
sudo CNI_COMMAND=ADD CNI_CONTAINERID=test123 CNI_NETNS=/proc/1/ns/net \
CNI_IFNAME=eth0 CNI_PATH=/opt/cni/bin /opt/cni/bin/headcni
```

### 构建系统

```bash
# 基本构建
make build                    # 构建当前平台
make clean                    # 清理构建文件

# 多架构构建
make build-linux-amd64       # Linux AMD64
make build-windows-amd64     # Windows AMD64
make build-darwin-amd64      # macOS AMD64

# 批量构建
make build-all-linux         # 所有Linux架构
make build-all               # 所有平台架构
```

### 支持的架构

- **Linux**: 386, amd64, arm, arm64, s390x, ppc64le, riscv64
- **Windows**: amd64, arm64
- **macOS**: amd64, arm64

---

<div align="center">

**由HeadCNI团队用心制作 ❤️**

[![GitHub](https://img.shields.io/badge/GitHub-100000?style=for-the-badge&logo=github&logoColor=white)](https://github.com/binrclab/headcni-plugin)
[![Issues](https://img.shields.io/badge/Issues-100000?style=for-the-badge&logo=github&logoColor=white)](https://github.com/binrclab/headcni-plugin/issues)
[![Pull Requests](https://img.shields.io/badge/Pull%20Requests-100000?style=for-the-badge&logo=github&logoColor=white)](https://github.com/binrclab/headcni-plugin/pulls)

</div> 