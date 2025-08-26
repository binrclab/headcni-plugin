#!/bin/bash
# scripts/package.sh - 创建发布包脚本

set -e

PROGRAM="headcni"
VERSION="${VERSION:-1.0.0}"
RELEASE_DIR="release"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}[PACKAGE]${NC} Creating release packages for $PROGRAM v$VERSION"

# 创建发布目录
mkdir -p "$RELEASE_DIR"
rm -rf "$RELEASE_DIR"/*

# 所有构建的二进制文件
BINARIES=(
    "headcni-linux-386"
    "headcni-linux-amd64" 
    "headcni-linux-arm"
    "headcni-linux-arm64"
    "headcni-linux-s390x"
    "headcni-linux-ppc64le"
    "headcni-linux-riscv64"
    "headcni-windows-amd64.exe"
    "headcni-windows-arm64.exe"
    "headcni-darwin-amd64"
    "headcni-darwin-arm64"
)

# 创建 README 文件
cat > "$RELEASE_DIR/README.md" << 'EOF'
# HeadCNI Plugin Binary Release

## Installation

### Linux/macOS
```bash
# Make executable
chmod +x headcni

# Install to CNI bin directory
sudo mv headcni /opt/cni/bin/

# Verify installation
/opt/cni/bin/headcni --version
```

### Windows
```cmd
# Copy to CNI bin directory
copy headcni.exe C:\opt\cni\bin\

# Verify installation
C:\opt\cni\bin\headcni.exe --version
```

## Configuration

Create a CNI configuration file:

```json
{
  "cniVersion": "0.4.0",
  "name": "headcni-network", 
  "plugins": [
    {
      "type": "headcni",
      "delegate": {
        "type": "bridge",
        "bridge": "cni0"
      }
    }
  ]
}
```

## Documentation

Visit https://github.com/binrc/headcni-plugin for full documentation.
EOF

# 为每个二进制文件创建包
for binary in "${BINARIES[@]}"; do
    if [ -f "dist/$binary" ]; then
        echo -e "${BLUE}[PACKAGE]${NC} Packaging $binary"
        
        # 提取平台和架构信息
        if [[ $binary == *"windows"* ]]; then
            platform_arch=$(echo "$binary" | sed 's/headcni-//' | sed 's/\.exe$//')
            archive_name="$PROGRAM-$platform_arch.zip"
            
            # 创建临时目录
            temp_dir="temp_$platform_arch"
            mkdir -p "$temp_dir"
            
            # 复制文件
            cp "dist/$binary" "$temp_dir/headcni.exe"
            cp "$RELEASE_DIR/README.md" "$temp_dir/"
            
            # 创建 zip 包
            (cd "$temp_dir" && zip -r "../$RELEASE_DIR/$archive_name" .)
            
            # 清理
            rm -rf "$temp_dir"
        else
            platform_arch=$(echo "$binary" | sed 's/headcni-//')
            archive_name="$PROGRAM-$platform_arch.tar.gz"
            
            # 创建临时目录
            temp_dir="temp_$platform_arch"
            mkdir -p "$temp_dir"
            
            # 复制文件
            cp "dist/$binary" "$temp_dir/headcni"
            chmod +x "$temp_dir/headcni"
            cp "$RELEASE_DIR/README.md" "$temp_dir/"
            
            # 创建 tar.gz 包
            tar -czf "$RELEASE_DIR/$archive_name" -C "$temp_dir" .
            
            # 清理
            rm -rf "$temp_dir"
        fi
        
        echo -e "${GREEN}[SUCCESS]${NC} Created $archive_name"
    else
        echo -e "${YELLOW}[WARNING]${NC} Binary dist/$binary not found, skipping"
    fi
done

# 生成校验和
echo -e "${BLUE}[PACKAGE]${NC} Generating checksums"
(cd "$RELEASE_DIR" && find . -name "*.tar.gz" -o -name "*.zip" | xargs sha256sum > checksums.sha256)

# 显示结果
echo -e "${GREEN}[SUCCESS]${NC} Release packages created:"
ls -la "$RELEASE_DIR"

echo -e "${GREEN}[SUCCESS]${NC} Release packages created in $RELEASE_DIR"