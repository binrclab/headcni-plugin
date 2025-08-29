# HeadCNI Configuration Examples

## 1. CNI Network Configuration (10-headcni.conf)

```json
{
  "name": "cbr0",
  "cniVersion": "0.3.1",
  "plugins": [
    {
      "type": "headcni",
      "subnetFile": "/run/headcni/subnet.yaml",
      "dataDir": "/var/lib/cni/headcni",
      "delegate": {
        "hairpinMode": true,
        "isDefaultGateway": true
      }
    },
    {
      "type": "portmap",
      "capabilities": {
        "portMappings": true
      }
    }
  ]
}
```

## 2. Subnet YAML Configuration (subnet.yaml)

```yaml
# Headcni Environment Configuration
# This file defines the network environment for the headcni plugin

# IPv4 network configuration
network: 10.43.0.0/16                        # IPv4 network configuration (pod CIDR)
subnet: 10.42.9.0/24                         # IPv4 subnet configuration

# IPv6 network configuration (optional)
ipv6_network: ""                             # IPv6 network configuration (pod CIDR)
ipv6_subnet: ""                              # IPv6 subnet configuration

# MTU for the network interface
mtu: 1230                                    # MTU configuration

# IP masquerading configuration
# true = enable masquerading, false = disable
ipmasq: true                                 # IP masquerade configuration

# Additional metadata (optional)
metadata:                                    # Metadata information
  generated_at: "2025-08-28T11:55:10Z"         # Generation timestamp
  node_name: cn-guizhou-worker-gpu-001         # Node name
  cluster_cidr: 10.42.9.0/24                   # Cluster CIDR
  service_cidr: 10.43.0.0/16                   # Service CIDR

# Route configuration (optional)
routes:                                      # Routes configuration
  - dst: 10.43.0.0/16                   # Destination CIDR
    gw: 10.42.9.1                        # Gateway IP
  - dst: 0.0.0.0/0                      # Default route
    gw: 10.42.9.1                        # Gateway IP

# DNS configuration (optional)
dns:                                         # DNS configuration
  nameservers:                             # DNS nameservers
  - "10.43.0.10"                          # Primary DNS
  - "8.8.8.8"                             # Google DNS
  - "8.8.4.4"                             # Google DNS secondary
  search:                                  # DNS search domains
  - cluster.local
  - svc.cluster.local
  options:                                 # DNS options
  - "ndots:5"
  - "timeout:2"

# Network policies (optional)
policies: null
```

## 3. Minimal Configuration Example

```yaml
# Minimal headcni subnet configuration
network: 10.244.0.0/16
subnet: 10.244.1.0/
```