# HeadCNI Plugin v1.0.0 Makefile

# 版本信息
PROGRAM := headcni
VERSION := 1.0.0
COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "dev")
BUILD_DATE := $(shell date -u '+%Y-%m-%d_%H:%M:%S')

# Go 编译参数 - CGO在amd64上启用
ifeq ($(ARCH),amd64)
    CGO_ENABLED := 1
    GO_FLAGS := -ldflags "-X main.Program=$(PROGRAM) -X main.Version=$(VERSION) -X main.Commit=$(COMMIT) -X main.buildDate=$(BUILD_DATE)"
    GO_BUILD := go build $(GO_FLAGS)
else
    CGO_ENABLED := 0
    GO_FLAGS := -ldflags "-X main.Program=$(PROGRAM) -X main.Version=$(VERSION) -X main.Commit=$(COMMIT) -X main.buildDate=$(BUILD_DATE)"
    GO_BUILD := CGO_ENABLED=0 go build $(GO_FLAGS)
endif

# 检测操作系统
UNAME_S := $(shell uname -s 2>/dev/null || echo "Unknown")
UNAME_M := $(shell uname -m 2>/dev/null || echo "Unknown")

# 设置默认目标平台
ifeq ($(UNAME_S),Linux)
    OS := linux
    CNI_BIN_DIR := /opt/cni/bin
    CNI_CONF_DIR := /etc/cni/net.d
endif
ifeq ($(UNAME_S),Darwin)
    OS := darwin
    CNI_BIN_DIR := /opt/cni/bin
    CNI_CONF_DIR := /etc/cni/net.d
endif
ifneq (,$(findstring MINGW,$(UNAME_S)))
    OS := windows
    CNI_BIN_DIR := C:/opt/cni/bin
    CNI_CONF_DIR := C:/etc/cni/net.d
endif
ifneq (,$(findstring MSYS,$(UNAME_S)))
    OS := windows
    CNI_BIN_DIR := C:/opt/cni/bin
    CNI_CONF_DIR := C:/etc/cni/net.d
endif

# 架构检测
ifeq ($(UNAME_M),x86_64)
    ARCH := amd64
endif
ifeq ($(UNAME_M),aarch64)
    ARCH := arm64
endif
ifeq ($(UNAME_M),arm64)
    ARCH := arm64
endif

# 默认值
OS ?= linux
ARCH ?= amd64

# 输出文件名
ifeq ($(OS),windows)
    BINARY := $(PROGRAM).exe
else
    BINARY := $(PROGRAM)
endif

# 颜色定义
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

.PHONY: all build build-linux build-linux-386 build-linux-amd64 build-linux-arm build-linux-arm64 build-linux-s390x build-linux-ppc64le build-linux-riscv64 build-windows build-windows-arm64 build-darwin build-darwin-arm64 build-all install clean test help version

# 默认目标
all: build

# 构建当前平台版本
build:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for $(OS)/$(ARCH) (CGO_ENABLED=$(CGO_ENABLED))"
	@GOOS=$(OS) GOARCH=$(ARCH) $(GO_BUILD) -o $(BINARY) .
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(BINARY)"

# 使用脚本构建 Linux 386 版本
build-linux-386:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for linux/386"
	@GOOS=linux GOARCH=386 ./scripts/build_headcni.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(PROGRAM)-linux-386"

# 使用脚本构建 Linux AMD64 版本 (启用CGO)
build-linux-amd64:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for linux/amd64 (CGO enabled)"
	@GOOS=linux GOARCH=amd64 ./scripts/build_headcni.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(PROGRAM)-linux-amd64"

# 使用脚本构建 Linux ARM 版本
build-linux-arm:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for linux/arm"
	@GOOS=linux GOARCH=arm ./scripts/build_headcni.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(PROGRAM)-linux-arm"

# 使用脚本构建 Linux ARM64 版本
build-linux-arm64:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for linux/arm64"
	@GOOS=linux GOARCH=arm64 ./scripts/build_headcni.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(PROGRAM)-linux-arm64"

# 使用脚本构建 Linux S390X 版本
build-linux-s390x:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for linux/s390x"
	@GOOS=linux GOARCH=s390x ./scripts/build_headcni.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(PROGRAM)-linux-s390x"

# 使用脚本构建 Linux PPC64LE 版本
build-linux-ppc64le:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for linux/ppc64le"
	@GOOS=linux GOARCH=ppc64le ./scripts/build_headcni.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(PROGRAM)-linux-ppc64le"

# 使用脚本构建 Linux RISCV64 版本
build-linux-riscv64:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for linux/riscv64"
	@GOOS=linux GOARCH=riscv64 ./scripts/build_headcni.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(PROGRAM)-linux-riscv64"

# 使用脚本构建 Windows AMD64 版本 (启用CGO)
build-windows:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for windows/amd64 (CGO enabled)"
	@GOOS=windows GOARCH=amd64 ./scripts/build_headcni.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(PROGRAM)-windows-amd64.exe"

# 使用脚本构建 Windows ARM64 版本
build-windows-arm64:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for windows/arm64"
	@GOOS=windows GOARCH=arm64 ./scripts/build_headcni.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(PROGRAM)-windows-arm64.exe"

# 使用脚本构建 macOS AMD64 版本 (启用CGO)
build-darwin:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for darwin/amd64 (CGO enabled)"
	@GOOS=darwin GOARCH=amd64 ./scripts/build_headcni.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(PROGRAM)-darwin-amd64"

# 使用脚本构建 macOS ARM64 版本 (Apple Silicon)
build-darwin-arm64:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for darwin/arm64"
	@GOOS=darwin GOARCH=arm64 ./scripts/build_headcni.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(PROGRAM)-darwin-arm64"

# 构建所有平台版本
build-all: build-linux-386 build-linux-amd64 build-linux-arm build-linux-arm64 build-linux-s390x build-linux-ppc64le build-linux-riscv64 build-windows build-windows-arm64 build-darwin build-darwin-arm64
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built all platform binaries"

# 构建所有Linux版本
build-all-linux: build-linux-386 build-linux-amd64 build-linux-arm build-linux-arm64 build-linux-s390x build-linux-ppc64le build-linux-riscv64
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built all Linux platform binaries"

# 使用脚本构建所有Linux版本
build-all-linux-script:
	@echo -e "$(BLUE)[BUILD]$(NC) Building all Linux architectures using script"
	@chmod +x ./scripts/build_all_linux.sh
	@./scripts/build_all_linux.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) All Linux architectures built"

# 使用脚本构建所有平台版本
build-all-script:
	@echo -e "$(BLUE)[BUILD]$(NC) Building all platforms using script"
	@chmod +x ./scripts/build_all_platforms.sh
	@./scripts/build_all_platforms.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) All platforms built"

# 构建特定版本和架构
build-version:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for $(GOOS)/$(GOARCH)"
	@GOOS=$(GOOS) GOARCH=$(GOARCH) ./scripts/build_headcni.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(PROGRAM)-$(GOOS)-$(GOARCH)$(if $(findstring windows,$(GOOS)),.exe,)"

# 构建多个版本
build-versions:
	@echo -e "$(BLUE)[BUILD]$(NC) Building multiple versions of $(PROGRAM)"
	@$(MAKE) build-all-linux
	@$(MAKE) build-windows
	@$(MAKE) build-windows-arm64
	@$(MAKE) build-darwin
	@$(MAKE) build-darwin-arm64
	@echo -e "$(GREEN)[SUCCESS]$(NC) All versions built"

# 安装到系统 CNI 目录
install: build
	@echo -e "$(BLUE)[INSTALL]$(NC) Installing $(BINARY) to $(CNI_BIN_DIR)"
ifeq ($(OS),windows)
	@mkdir -p "$(CNI_BIN_DIR)" 2>/dev/null || true
	@cp $(BINARY) "$(CNI_BIN_DIR)/"
else
	@sudo mkdir -p $(CNI_BIN_DIR)
	@sudo cp $(BINARY) $(CNI_BIN_DIR)/
	@sudo chmod +x $(CNI_BIN_DIR)/$(BINARY)
endif
	@echo -e "$(GREEN)[SUCCESS]$(NC) Installed $(BINARY)"

# 卸载
uninstall:
	@echo -e "$(YELLOW)[UNINSTALL]$(NC) Removing $(BINARY) from $(CNI_BIN_DIR)"
ifeq ($(OS),windows)
	@rm -f "$(CNI_BIN_DIR)/$(BINARY)" 2>/dev/null || true
else
	@sudo rm -f $(CNI_BIN_DIR)/$(BINARY)
endif
	@echo -e "$(GREEN)[SUCCESS]$(NC) Uninstalled $(BINARY)"

# 创建示例配置文件
config:
	@echo -e "$(BLUE)[CONFIG]$(NC) Creating example configuration files"
	@mkdir -p "$(CNI_CONF_DIR)" 2>/dev/null || true
	@cat > "$(CNI_CONF_DIR)/10-headcni-example.conflist" << 'EOF'
	{
	  "cniVersion": "0.4.0",
	  "name": "headcni-example",
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
	EOF
	@cat > "$(CNI_CONF_DIR)/20-headcni-chain-example.conflist" << 'EOF'
	{
	  "cniVersion": "0.4.0",
	  "name": "headcni-chain-example",
	  "plugins": [
	    {
	      "type": "headcni",
	      "plugins": [
	        {
	          "type": "headcni",
	          "delegate": {
	            "type": "bridge"
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
	  ]
	}
	EOF
	@echo -e "$(GREEN)[SUCCESS]$(NC) Created example configurations in $(CNI_CONF_DIR)"

# 运行测试
test:
	@echo -e "$(BLUE)[TEST]$(NC) Running Go tests"
	@go test -v ./...
	@echo -e "$(GREEN)[SUCCESS]$(NC) All tests passed"

# 运行集成测试
integration-test: build
	@echo -e "$(BLUE)[TEST]$(NC) Running integration tests"
	@if [ -f "./test.sh" ]; then \
		chmod +x ./test.sh && ./test.sh --test; \
	else \
		echo -e "$(YELLOW)[WARNING]$(NC) Integration test script not found"; \
	fi

# 完整测试流程
test-all: build install config integration-test
	@echo -e "$(GREEN)[SUCCESS]$(NC) Complete test suite finished"

# 清理构建文件
clean:
	@echo -e "$(YELLOW)[CLEAN]$(NC) Cleaning build artifacts"
	@rm -f $(PROGRAM) $(PROGRAM).exe
	@rm -f $(PROGRAM)-linux-* $(PROGRAM)-windows-* $(PROGRAM)-darwin-*
	@rm -rf dist/
	@echo -e "$(GREEN)[SUCCESS]$(NC) Cleaned build artifacts"

# 清理配置和数据
clean-all: clean uninstall
	@echo -e "$(YELLOW)[CLEAN]$(NC) Cleaning configurations and data"
ifeq ($(OS),windows)
	@rm -rf "C:/var/lib/cni/headcni" 2>/dev/null || true
	@rm -f "$(CNI_CONF_DIR)"/*headcni*.conflist 2>/dev/null || true
else
	@sudo rm -rf /var/lib/cni/headcni
	@sudo rm -f $(CNI_CONF_DIR)/*headcni*.conflist
endif
	@echo -e "$(GREEN)[SUCCESS]$(NC) Cleaned all files"

# 检查依赖
check-deps:
	@echo -e "$(BLUE)[CHECK]$(NC) Checking dependencies"
	@go version >/dev/null 2>&1 || (echo -e "$(RED)[ERROR]$(NC) Go is not installed" && exit 1)
	@echo -e "$(GREEN)[SUCCESS]$(NC) Go: $(shell go version)"
	@if command -v git >/dev/null 2>&1; then \
		echo -e "$(GREEN)[SUCCESS]$(NC) Git: $(shell git --version)"; \
	else \
		echo -e "$(YELLOW)[WARNING]$(NC) Git is not installed (optional)"; \
	fi

# 代码格式化
fmt:
	@echo -e "$(BLUE)[FORMAT]$(NC) Formatting Go code"
	@go fmt ./...
	@echo -e "$(GREEN)[SUCCESS]$(NC) Code formatted"

# 代码检查
lint:
	@echo -e "$(BLUE)[LINT]$(NC) Running code analysis"
	@if command -v golangci-lint >/dev/null 2>&1; then \
		golangci-lint run; \
	else \
		echo -e "$(YELLOW)[WARNING]$(NC) golangci-lint not found, using go vet"; \
		go vet ./...; \
	fi
	@echo -e "$(GREEN)[SUCCESS]$(NC) Code analysis completed"

# 显示版本信息
version:
	@echo "$(PROGRAM) v$(VERSION)"
	@echo "Commit: $(COMMIT)"
	@echo "Built: $(BUILD_DATE)"
	@echo "Target: $(OS)/$(ARCH)"
	@echo "CGO: $(CGO_ENABLED)"

# 创建发布包
release: build-all
	@echo -e "$(BLUE)[RELEASE]$(NC) Creating release packages"
	@chmod +x ./scripts/package.sh
	@./scripts/package.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Release packages created in release/"

# 使用脚本创建发布包
release-script: build-all-script
	@echo -e "$(BLUE)[RELEASE]$(NC) Creating release packages using script"
	@chmod +x ./scripts/package.sh
	@./scripts/package.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Release packages created in release/"

# 开发环境设置
dev-setup: check-deps fmt lint test
	@echo -e "$(GREEN)[SUCCESS]$(NC) Development environment ready"

# 显示帮助信息
help:
	@echo "HeadCNI Plugin v$(VERSION) Makefile"
	@echo ""
	@echo "构建命令:"
	@echo "  build                构建当前平台版本 ($(OS)/$(ARCH))"
	@echo "  build-linux-386      构建 Linux 386 版本"
	@echo "  build-linux-amd64    构建 Linux amd64 版本 (CGO enabled)"
	@echo "  build-linux-arm      构建 Linux arm 版本"
	@echo "  build-linux-arm64    构建 Linux arm64 版本"  
	@echo "  build-linux-s390x    构建 Linux s390x 版本"
	@echo "  build-linux-ppc64le  构建 Linux ppc64le 版本"
	@echo "  build-linux-riscv64  构建 Linux riscv64 版本"
	@echo "  build-windows        构建 Windows amd64 版本 (CGO enabled)"
	@echo "  build-windows-arm64  构建 Windows arm64 版本"
	@echo "  build-darwin         构建 macOS amd64 版本 (CGO enabled)"
	@echo "  build-darwin-arm64   构建 macOS arm64 版本 (Apple Silicon)"
	@echo "  build-all            构建所有平台版本"
	@echo "  build-all-linux      构建所有Linux平台版本"
	@echo "  build-all-linux-script 使用脚本构建所有Linux版本"
	@echo "  build-all-script     使用脚本构建所有平台版本"
	@echo "  build-versions       构建所有版本 (别名)"
	@echo "  build-version        构建特定版本 (需要设置 GOOS 和 GOARCH)"
	@echo ""
	@echo "安装命令:"
	@echo "  install              安装到系统 CNI 目录"
	@echo "  uninstall            从系统中卸载"
	@echo "  config               创建示例配置文件"
	@echo ""
	@echo "测试命令:"
	@echo "  test                 运行单元测试"
	@echo "  integration-test     运行集成测试"
	@echo "  test-all             运行完整测试套件"
	@echo ""
	@echo "开发命令:"
	@echo "  check-deps           检查依赖项"
	@echo "  fmt                  格式化代码"
	@echo "  lint                 代码静态分析"
	@echo "  dev-setup            设置开发环境"
	@echo ""
	@echo "其他命令:"
	@echo "  clean                清理构建文件"
	@echo "  clean-all            清理所有文件"
	@echo "  release              创建发布包"
	@echo "  release-script       使用脚本创建发布包"
	@echo "  version              显示版本信息"
	@echo "  help                 显示此帮助信息"
	@echo ""
	@echo "示例:"
	@echo "  make build install   # 构建并安装"
	@echo "  make test-all        # 完整测试"
	@echo "  make release         # 创建发布版本"
	@echo "  make build-version GOOS=linux GOARCH=arm64  # 构建特定版本"
	@echo "  make build-all-linux # 构建所有Linux版本"
	@echo "  make build-all-script # 使用脚本构建所有平台"

# 设置默认目标
.DEFAULT_GOAL := help