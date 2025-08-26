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

Visit https://github.com/your-org/headcni for full documentation.
EOF

# 为每个二进制文件创建包
for binary in "${BINARIES[@]}"; do
    if [ -f "$binary" ]; then
        echo -e "${BLUE}[PACKAGE]${NC} Packaging $binary"
        
        # 提取平台和架构信息
        if [[ $binary == *"windows"* ]]; then
            platform_arch=$(echo "$binary" | sed 's/headcni-//' | sed 's/\.exe$//')
            archive_name="$PROGRAM-$platform_arch.zip"
            
            # 创建临时目录
            temp_dir="temp_$platform_arch"
            mkdir -p "$temp_dir"
            
            # 复制文件
            cp "$binary" "$temp_dir/headcni.exe"
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
            cp "$binary" "$temp_dir/headcni"
            chmod +x "$temp_dir/headcni"
            cp "$RELEASE_DIR/README.md" "$temp_dir/"
            
            # 创建 tar.gz 包
            tar -czf "$RELEASE_DIR/$archive_name" -C "$temp_dir" .
            
            # 清理
            rm -rf "$temp_dir"
        fi
        
        echo -e "${GREEN}[SUCCESS]${NC} Created $archive_name"
    else
        echo -e "${YELLOW}[WARNING]${NC} Binary $binary not found, skipping"
    fi
done

# 生成校验和
echo -e "${BLUE}[PACKAGE]${NC} Generating checksums"
(cd "$RELEASE_DIR" && find . -name "*.tar.gz" -o -name "*.zip" | xargs sha256sum > checksums.sha256)

# 显示结果
echo -e "${GREEN}[SUCCESS]${NC} Release packages created:"
ls -la "$RELEASE_DIR"

echo -e "${GREEN}[SUCCESS]${NC} Release packaging complete!"

---

# scripts/build_all_platforms.sh - 构建所有平台脚本

#!/bin/bash

set -e

PROGRAM="headcni"
VERSION="${VERSION:-1.0.0}"
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
BUILD_DATE=$(date -u '+%Y-%m-%d_%H:%M:%S')

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m' 
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}[BUILD]${NC} Building $PROGRAM v$VERSION for all platforms"

# 构建函数
build_binary() {
    local goos=$1
    local goarch=$2
    local cgo_enabled=$3
    
    local output_name="$PROGRAM-$goos-$goarch"
    if [[ $goos == "windows" ]]; then
        output_name="$output_name.exe"
    fi
    
    echo -e "${BLUE}[BUILD]${NC} Building $output_name (CGO_ENABLED=$cgo_enabled)"
    
    local ldflags="-X main.Program=$PROGRAM -X main.Version=$VERSION -X main.Commit=$COMMIT -X main.buildDate=$BUILD_DATE"
    
    if [[ $cgo_enabled == "1" ]]; then
        CGO_ENABLED=1 GOOS=$goos GOARCH=$goarch go build -ldflags "$ldflags" -o "$output_name" .
    else
        CGO_ENABLED=0 GOOS=$goos GOARCH=$goarch go build -ldflags "$ldflags" -o "$output_name" .
    fi
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} Built $output_name"
    else
        echo -e "${RED}[ERROR]${NC} Failed to build $output_name"
        return 1
    fi
}

# 清理旧文件
echo -e "${YELLOW}[CLEAN]${NC} Cleaning old binaries"
rm -f headcni-*

# 构建所有平台
echo -e "${BLUE}[BUILD]${NC} Starting multi-platform build"

# Linux 平台
build_binary "linux" "386" "0"
build_binary "linux" "amd64" "1"  # CGO enabled for amd64
build_binary "linux" "arm" "0" 
build_binary "linux" "arm64" "0"
build_binary "linux" "s390x" "0"
build_binary "linux" "ppc64le" "0"
build_binary "linux" "riscv64" "0"

# Windows 平台  
build_binary "windows" "amd64" "1"  # CGO enabled for amd64
build_binary "windows" "arm64" "0"

# macOS 平台
build_binary "darwin" "amd64" "1"   # CGO enabled for amd64
build_binary "darwin" "arm64" "0"

echo -e "${GREEN}[SUCCESS]${NC} All platform builds completed!"
echo -e "${BLUE}[INFO]${NC} Built binaries:"
ls -la headcni-*

---

# scripts/build_headcni.sh - 单个构建脚本

#!/bin/bash

set -e

PROGRAM="headcni"
VERSION="${VERSION:-1.0.0}"
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
BUILD_DATE=$(date -u '+%Y-%m-%d_%H:%M:%S')

# 从环境变量获取目标平台
TARGET_OS="${GOOS:-linux}"
TARGET_ARCH="${GOARCH:-amd64}"

# 确定是否启用 CGO (amd64 平台默认启用)
if [[ $TARGET_ARCH == "amd64" ]]; then
    CGO_ENABLED="${CGO_ENABLED:-1}"
else
    CGO_ENABLED="${CGO_ENABLED:-0}"
fi

# 输出文件名
OUTPUT_NAME="$PROGRAM-$TARGET_OS-$TARGET_ARCH"
if [[ $TARGET_OS == "windows" ]]; then
    OUTPUT_NAME="$OUTPUT_NAME.exe"
fi

# 构建标志
LDFLAGS="-X main.Program=$PROGRAM -X main.Version=$VERSION -X main.Commit=$COMMIT -X main.buildDate=$BUILD_DATE"

# 颜色定义
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}[BUILD]${NC} Building $OUTPUT_NAME (CGO_ENABLED=$CGO_ENABLED)"

# 执行构建
if [[ $CGO_ENABLED == "1" ]]; then
    CGO_ENABLED=1 GOOS=$TARGET_OS GOARCH=$TARGET_ARCH go build -ldflags "$LDFLAGS" -o "$OUTPUT_NAME" .
else
    CGO_ENABLED=0 GOOS=$TARGET_OS GOARCH=$TARGET_ARCH go build -ldflags "$LDFLAGS" -o "$OUTPUT_NAME" .
fi

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}[SUCCESS]${NC} Built $OUTPUT_NAME"
    ls -la "$OUTPUT_NAME"
else
    echo -e "${RED}[ERROR]${NC} Failed to build $OUTPUT_NAME"
    exit 1
fi