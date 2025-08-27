#!/bin/sh

# 设置默认值，如果环境变量未设置
TARGETOS="${TARGETOS:-linux}"
TARGETARCH="${TARGETARCH:-amd64}"

echo "Using TARGETOS=$TARGETOS, TARGETARCH=$TARGETARCH"

# 根据宿主机 OS/ARCH 选择二进制
if [ "$TARGETOS" = "windows" ]; then
    BIN="/app/headcni-windows-$TARGETARCH.exe"
    TARGET_FILE="headcni.exe"
else
    BIN="/app/headcni-$TARGETOS-$TARGETARCH"
    TARGET_FILE="headcni"
fi

# 检查二进制文件是否存在
if [ ! -f "$BIN" ]; then
    echo "Error: Binary $BIN not found."
    exit 1
fi

echo "Found binary: $BIN"

# 处理不同的命令模式
case "${1:-install}" in
    "install")
        # 安装模式：复制到目标目录
        if [ "$TARGETOS" = "windows" ]; then
            TARGET_DIR="${CNI_BIN_DIR:-C:\\Program Files\\CNI\\bin}"
        else
            TARGET_DIR="${CNI_BIN_DIR:-/opt/cni/bin}"
        fi
        
        # 创建目标目录（如果不存在）
        if [ "$TARGETOS" = "windows" ]; then
            # Windows 使用 PowerShell 创建目录
            powershell -Command "New-Item -ItemType Directory -Force -Path '$TARGET_DIR'" 2>/dev/null || true
        else
            mkdir -p "$TARGET_DIR"
        fi
        
        # 复制二进制文件
        echo "Installing $BIN to $TARGET_DIR/$TARGET_FILE"
        if [ "$TARGETOS" = "windows" ]; then
            cp "$BIN" "$TARGET_DIR/$TARGET_FILE"
            # Windows 不需要 chmod
        else
            cp "$BIN" "$TARGET_DIR/$TARGET_FILE"
            chmod +x "$TARGET_DIR/$TARGET_FILE"
        fi
        
        # 验证安装
        if [ -f "$TARGET_DIR/$TARGET_FILE" ]; then
            echo "Successfully installed $TARGET_FILE to $TARGET_DIR"
            if [ "$TARGETOS" = "windows" ]; then
                dir "$TARGET_DIR\\$TARGET_FILE"
            else
                ls -la "$TARGET_DIR/$TARGET_FILE"
            fi
        else
            echo "Error: Installation failed"
            exit 1
        fi
        ;;
    "exec")
        # 执行模式：直接运行二进制文件
        shift
        echo "Executing $BIN with args: $@"
        exec "$BIN" "$@"
        ;;
    "verify")
        # 验证模式：检查二进制文件
        echo "Verifying binary: $BIN"
        if command -v file >/dev/null 2>&1; then
            file "$BIN"
        else
            echo "file command not available, using alternative verification"
        fi
        echo "Binary size: $(ls -lh "$BIN" | awk '{print $5}')"
        echo "Binary permissions: $(ls -la "$BIN" | awk '{print $1}')"
        echo "Binary exists: $(test -f "$BIN" && echo "YES" || echo "NO")"
        echo "Binary executable: $(test -x "$BIN" && echo "YES" || echo "NO")"
        echo "Verification completed"
        exit 0
        ;;
    *)
        echo "Usage: $0 [install|exec|verify] [args...]"
        echo "  install: Copy binary to CNI_BIN_DIR (default)"
        echo "  exec: Execute binary directly"
        echo "  verify: Verify binary file"
        echo ""
        echo "Environment variables:"
        echo "  CNI_BIN_DIR: Target directory for installation (default: /opt/cni/bin)"
        echo "  CNI_BIN_NAME: Target filename (default: headcni)"
        echo "  TARGETOS: Target OS (default: linux)"
        echo "  TARGETARCH: Target architecture (default: amd64)"
        exit 1
        ;;
esac


# 根据宿主机 OS/ARCH 拷贝二进制
if [ "$TARGETOS" = "windows" ]; then
    BIN="/app/headcni-windows-$TARGETARCH.exe"
else
    BIN="/app/headcni-$TARGETOS-$TARGETARCH"
fi

if [ ! -f "$BIN" ]; then
    echo "Error: Binary $BIN not found."
    exit 1
fi

# 拷贝并设置权限
cp "$BIN" "$TARGET_DIR/$TARGET_FILE"
chmod +x "$TARGET_DIR/$TARGET_FILE" || true

echo "Successfully installed $BIN to $TARGET_DIR"
ls -la "$TARGET_DIR"
