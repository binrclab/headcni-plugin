# HeadCNI Plugin v1.0.0 Makefile

# 版本信息
PROGRAM := headcni
VERSION := 1.0.0
COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "dev")
BUILD_DATE := $(shell date -u '+%Y-%m-%d_%H:%M:%S')

# Go 编译参数 - 支持静态链接和动态链接
ifeq ($(ARCH),amd64)
    # 默认启用CGO，但支持静态链接
    CGO_ENABLED := 1
    GO_FLAGS := -ldflags "-X main.Program=$(PROGRAM) -X main.Version=$(VERSION) -X main.Commit=$(COMMIT) -X main.buildDate=$(BUILD_DATE)"
    GO_BUILD := go build $(GO_FLAGS)
    # 静态链接版本
    GO_BUILD_STATIC := CGO_ENABLED=0 go build -ldflags "-X main.Program=$(PROGRAM) -X main.Version=$(VERSION) -X main.Commit=$(COMMIT) -X main.buildDate=$(BUILD_DATE) -s -w -extldflags '-static'"
else
    CGO_ENABLED := 0
    GO_FLAGS := -ldflags "-X main.Program=$(PROGRAM) -X main.Version=$(VERSION) -X main.Commit=$(COMMIT) -X main.buildDate=$(BUILD_DATE)"
    GO_BUILD := CGO_ENABLED=0 go build $(GO_FLAGS)
    # 静态链接版本
    GO_BUILD_STATIC := CGO_ENABLED=0 go build -ldflags "-X main.Program=$(PROGRAM) -X main.Version=$(VERSION) -X main.Commit=$(COMMIT) -X main.buildDate=$(BUILD_DATE) -s -w -extldflags '-static'"
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

# Docker 相关变量
DOCKER_IMAGE := headcni-plugin
DOCKER_REGISTRY := binrclab
DOCKER_NAMESPACE := headcni-plugin
DOCKER_TAG := $(VERSION)

# 支持的架构
SUPPORTED_ARCHS := linux/amd64 linux/arm64 linux/arm/v7 linux/arm/v8
ARCH_TAGS := amd64 arm64 armv7 armv8

# 颜色定义
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

.PHONY: all build build-static build-linux build-linux-386 build-linux-amd64 build-linux-amd64-static build-linux-arm build-linux-arm64 build-linux-s390x build-linux-ppc64le build-linux-riscv64 build-all-linux-with-static build-windows build-windows-arm64 build-darwin build-darwin-arm64 build-all install clean test help version docker docker-multiarch docker-push docker-clean

# 默认目标
all: build

# 构建当前平台版本
build:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for $(OS)/$(ARCH) (CGO_ENABLED=$(CGO_ENABLED))"
	@GOOS=$(OS) GOARCH=$(ARCH) $(GO_BUILD) -o $(BINARY) .
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(BINARY)"

# 构建静态链接版本
build-static:
	@echo -e "$(BLUE)[BUILD]$(NC) Building static $(PROGRAM) v$(VERSION) for $(OS)/$(ARCH)"
	@GOOS=$(OS) GOARCH=$(ARCH) $(GO_BUILD_STATIC) -o $(PROGRAM)-static .
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built static $(PROGRAM)-static"

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

# 构建静态链接的 Linux AMD64 版本
build-linux-amd64-static:
	@echo -e "$(BLUE)[BUILD]$(NC) Building static $(PROGRAM) v$(VERSION) for linux/amd64"
	@GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags "-X main.Program=$(PROGRAM) -X main.Version=$(VERSION) -X main.Commit=$(COMMIT) -X main.buildDate=$(BUILD_DATE) -s -w -extldflags '-static'" -o $(PROGRAM)-linux-amd64-static .
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built static $(PROGRAM)-linux-amd64-static"

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

# 构建所有 Linux 架构版本
build-linux: build-linux-386 build-linux-amd64 build-linux-arm build-linux-arm64 build-linux-s390x build-linux-ppc64le build-linux-riscv64

# 使用脚本构建 Windows AMD64 版本
build-windows-amd64:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for windows/amd64"
	@GOOS=windows GOARCH=amd64 ./scripts/build_headcni.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(PROGRAM)-windows-amd64.exe"

# 使用脚本构建 Windows ARM64 版本
build-windows-arm64:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for windows/arm64"
	@GOOS=windows GOARCH=arm64 ./scripts/build_headcni.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(PROGRAM)-windows-arm64.exe"

# 构建所有 Windows 架构版本
build-windows: build-windows-amd64 build-windows-arm64

# 使用脚本构建 macOS AMD64 版本
build-darwin-amd64:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for darwin/amd64"
	@GOOS=darwin GOARCH=amd64 ./scripts/build_headcni.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(PROGRAM)-darwin-amd64"

# 使用脚本构建 macOS ARM64 版本
build-darwin-arm64:
	@echo -e "$(BLUE)[BUILD]$(NC) Building $(PROGRAM) v$(VERSION) for darwin/arm64"
	@GOOS=darwin GOARCH=arm64 ./scripts/build_headcni.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built $(PROGRAM)-darwin-arm64"

# 构建所有 macOS 架构版本
build-darwin: build-darwin-amd64 build-darwin-arm64

# 构建所有平台和架构版本
build-all: build-linux build-windows build-darwin

# 构建所有平台版本
build-all: build-linux-386 build-linux-amd64 build-linux-arm build-linux-arm64 build-linux-s390x build-linux-ppc64le build-linux-riscv64 build-windows build-windows-arm64 build-darwin build-darwin-arm64
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built all platform binaries"

# Docker 相关目标
.PHONY: docker
docker: 
	@echo -e "$(BLUE)[DOCKER]$(NC) 构建 Docker 镜像..."
	docker build -f .docker/Dockerfile -t $(DOCKER_REGISTRY)/$(DOCKER_IMAGE):$(DOCKER_TAG) .
	docker tag $(DOCKER_REGISTRY)/$(DOCKER_IMAGE):$(DOCKER_TAG) $(DOCKER_REGISTRY)/$(DOCKER_IMAGE):latest
	@echo -e "$(GREEN)[SUCCESS]$(NC) Docker 镜像构建完成: $(DOCKER_REGISTRY)/$(DOCKER_IMAGE):$(DOCKER_TAG), $(DOCKER_REGISTRY)/$(DOCKER_IMAGE):latest"


# 多架构 Docker 构建
.PHONY: docker-multiarch
docker-multiarch:
	@echo -e "$(BLUE)[DOCKER]$(NC) 构建多架构 Docker 镜像..."
	@if [ -f "./scripts/build-multiarch-fixed.sh" ]; then \
		chmod +x ./scripts/build-multiarch-fixed.sh; \
		./scripts/build-multiarch-fixed.sh all; \
	else \
		echo -e "$(RED)[ERROR]$(NC) 多架构构建脚本不存在"; \
		exit 1; \
	fi
# 构建特定架构的 Docker 镜像
.PHONY: docker-build
docker-build:
	@echo -e "$(BLUE)[DOCKER]$(NC) 构建 Docker 镜像..."
	@if [ -f "./scripts/build-multiarch.sh" ]; then \
		chmod +x ./scripts/build-multiarch.sh; \
		./scripts/build-multiarch.sh build; \
	else \
		echo -e "$(RED)[ERROR]$(NC) 多架构构建脚本不存在: ./scripts/build-multiarch.sh"; \
		exit 1; \
	fi

# 创建多架构清单
.PHONY: docker-manifest
docker-manifest:
	@echo -e "$(BLUE)[DOCKER]$(NC) 创建多架构清单..."
	@if [ -f "./scripts/build-multiarch.sh" ]; then \
		chmod +x ./scripts/build-multiarch.sh; \
		./scripts/build-multiarch.sh manifest; \
	else \
		echo -e "$(RED)[ERROR]$(NC) 多架构构建脚本不存在: ./scripts/build-multiarch.sh"; \
		exit 1; \
	fi

# 创建统一的插件镜像
.PHONY: docker-unified
docker-unified:
	@echo -e "$(BLUE)[DOCKER]$(NC) 创建统一的插件镜像..."
	@if [ -f "./scripts/build-multiarch.sh" ]; then \
		chmod +x ./scripts/build-multiarch.sh; \
		./scripts/build-multiarch.sh unified; \
	else \
		echo -e "$(RED)[ERROR]$(NC) 多架构构建脚本不存在: ./scripts/build-multiarch.sh"; \
		exit 1; \
	fi

# 验证 Docker 镜像
.PHONY: docker-verify
docker-verify:
	@echo -e "$(BLUE)[DOCKER]$(NC) 验证 Docker 镜像..."
	@if [ -f "./scripts/build-multiarch.sh" ]; then \
		chmod +x ./scripts/build-multiarch.sh; \
		./scripts/build-multiarch.sh verify; \
	else \
		echo -e "$(RED)[ERROR]$(NC) 多架构构建脚本不存在: ./scripts/build-multiarch.sh"; \
		exit 1; \
	fi

# 推送 Docker 镜像
.PHONY: docker-push
docker-push:
	@echo -e "$(BLUE)[DOCKER]$(NC) 推送 Docker 镜像..."
	@if [ -f "./scripts/build-multiarch.sh" ]; then \
		chmod +x ./scripts/build-multiarch.sh; \
		PUSH_IMAGES=true ./scripts/build-multiarch.sh push; \
	else \
		echo -e "$(RED)[ERROR]$(NC) 多架构构建脚本不存在: ./scripts/build-multiarch.sh"; \
		exit 1; \
	fi

# 清理 Docker 镜像
.PHONY: docker-clean
docker-clean:
	@echo -e "$(BLUE)[DOCKER]$(NC) 清理 Docker 镜像..."
	@if [ -f "./scripts/build-multiarch.sh" ]; then \
		chmod +x ./scripts/build-multiarch.sh; \
		./scripts/build-multiarch.sh cleanup; \
	else \
		echo -e "$(RED)[ERROR]$(NC) 多架构构建脚本不存在: ./scripts/build-multiarch.sh"; \
		exit 1; \
	fi

# 清理并重新构建
.PHONY: docker-rebuild
docker-rebuild: docker-clean docker-multiarch

# 构建所有Linux版本
build-all-linux: build-linux-386 build-linux-amd64 build-linux-arm build-linux-arm64 build-linux-s390x build-linux-ppc64le build-linux-riscv64
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built all Linux platform binaries"

# 构建所有Linux版本（包括静态版本）
build-all-linux-with-static: build-linux-386 build-linux-amd64 build-linux-amd64-static build-linux-arm build-linux-arm64 build-linux-s390x build-linux-ppc64le build-linux-riscv64
	@echo -e "$(GREEN)[SUCCESS]$(NC) Built all Linux platform binaries (including static versions)"

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

# 清理并重新构建
.PHONY: docker-rebuild
docker-rebuild: docker-clean docker-multiarch

# 部署到本地
.PHONY: deploy-local
deploy-local:
	@echo -e "$(BLUE)[DEPLOY]$(NC) 部署到本地..."
	@if [ -f ".docker/docker-compose.yml" ]; then \
		docker-compose -f .docker/docker-compose.yml up -d; \
	else \
		echo -e "$(RED)[ERROR]$(NC) .docker/docker-compose.yml 文件不存在"; \
		exit 1; \
	fi

# 部署测试环境
.PHONY: deploy-test
deploy-test:
	@echo -e "$(BLUE)[DEPLOY]$(NC) 部署测试环境..."
	@if [ -f ".docker/docker-compose.yml" ]; then \
		docker-compose -f .docker/docker-compose.yml --profile test up -d; \
	else \
		echo -e "$(RED)[ERROR]$(NC) .docker/docker-compose.yml 文件不存在"; \
		exit 1; \
	fi

# 停止服务
.PHONY: stop
stop:
	@echo -e "$(BLUE)[STOP]$(NC) 停止服务..."
	@if [ -f ".docker/docker-compose.yml" ]; then \
		docker-compose -f .docker/docker-compose.yml down; \
	else \
		echo -e "$(RED)[ERROR]$(NC) .docker/docker-compose.yml 文件不存在"; \
		exit 1; \
	fi

# 查看服务状态
.PHONY: status
status:
	@echo -e "$(BLUE)[STATUS]$(NC) 查看服务状态..."
	@if [ -f ".docker/docker-compose.yml" ]; then \
		docker-compose -f .docker/docker-compose.yml ps; \
	else \
		echo -e "$(RED)[ERROR]$(NC) .docker/docker-compose.yml 文件不存在"; \
		exit 1; \
	fi

# 查看服务日志
.PHONY: logs
logs:
	@echo -e "$(BLUE)[LOGS]$(NC) 查看服务日志..."
	@if [ -f ".docker/docker-compose.yml" ]; then \
		docker-compose -f .docker/docker-compose.yml logs -f; \
	else \
		echo -e "$(RED)[ERROR]$(NC) .docker/docker-compose.yml 文件不存在"; \
		exit 1; \
	fi

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
	@echo -e "$(BLUE)[UNINSTALL]$(NC) Uninstalling $(PROGRAM) from $(CNI_BIN_DIR)"
	@sudo rm -f $(CNI_BIN_DIR)/$(PROGRAM)
	@echo -e "$(GREEN)[SUCCESS]$(NC) Uninstalled $(PROGRAM)"

# 清理构建文件
clean:
	@echo -e "$(YELLOW)[CLEAN]$(NC) Cleaning build artifacts"
	@rm -f $(PROGRAM) $(PROGRAM).exe
	@rm -f $(PROGRAM)-linux-* $(PROGRAM)-windows-* $(PROGRAM)-darwin-*
	@rm -rf dist/
	@echo -e "$(GREEN)[SUCCESS]$(NC) Cleaned build artifacts"

# 清理配置和数据
clean-all: clean
	@echo -e "$(YELLOW)[CLEAN]$(NC) Cleaning all files"
	@sudo rm -rf $(CNI_CONF_DIR)/10-headcni.conf
	@sudo rm -rf /var/lib/headcni
	@sudo rm -rf /var/run/headcni
	@echo -e "$(GREEN)[SUCCESS]$(NC) Cleaned all files"

# 运行测试
test:
	@echo -e "$(BLUE)[TEST]$(NC) Running tests..."
	go test -v ./...

# 运行集成测试
integration-test:
	@echo -e "$(BLUE)[TEST]$(NC) Running integration tests..."
	@echo "Integration tests not implemented yet"

# 运行完整测试套件
test-all: test integration-test
	@echo -e "$(GREEN)[SUCCESS]$(NC) All tests completed"

# 检查依赖项
check-deps:
	@echo -e "$(BLUE)[CHECK]$(NC) Checking dependencies..."
	@go mod verify
	@go mod tidy
	@echo -e "$(GREEN)[SUCCESS]$(NC) Dependencies checked"

# 格式化代码
fmt:
	@echo -e "$(BLUE)[FMT]$(NC) Formatting code..."
	go fmt ./...

# 代码静态分析
lint:
	@echo -e "$(BLUE)[LINT]$(NC) Running linter..."
	@if command -v golangci-lint >/dev/null; then \
		golangci-lint run; \
	else \
		echo "golangci-lint not installed, skipping"; \
	fi

# 设置开发环境
dev-setup: check-deps
	@echo -e "$(BLUE)[SETUP]$(NC) Setting up development environment..."
	@echo -e "$(GREEN)[SUCCESS]$(NC) Development environment ready"

# 创建发布包
release: build-all
	@echo -e "$(BLUE)[RELEASE]$(NC) Creating release package..."
	@mkdir -p dist
	@tar -czf dist/$(PROGRAM)-$(VERSION).tar.gz $(PROGRAM)-*
	@echo -e "$(GREEN)[SUCCESS]$(NC) Release package created: dist/$(PROGRAM)-$(VERSION).tar.gz"

# 使用脚本创建发布包
release-script:
	@echo -e "$(BLUE)[RELEASE]$(NC) Creating release package using script..."
	@chmod +x ./scripts/create_release.sh
	@./scripts/create_release.sh
	@echo -e "$(GREEN)[SUCCESS]$(NC) Release package created using script"

# 显示版本信息
version:
	@echo "$(PROGRAM) v$(VERSION)"
	@echo "Commit: $(COMMIT)"
	@echo "Built: $(BUILD_DATE)"
	@echo "Target: $(OS)/$(ARCH)"
	@echo "CGO: $(CGO_ENABLED)"

# 显示帮助信息
help:
	@echo "HeadCNI Plugin v$(VERSION) Makefile"
	@echo ""
	@echo "构建命令:"
	@echo "  build                构建当前平台版本 ($(OS)/$(ARCH))"
	@echo "  build-static         构建静态链接版本 ($(OS)/$(ARCH))"
	@echo "  build-linux-386      构建 Linux 386 版本"
	@echo "  build-linux-amd64    构建 Linux amd64 版本 (CGO enabled)"
	@echo "  build-linux-amd64-static 构建静态链接 Linux amd64 版本"
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
	@echo "  build-all-linux-with-static 构建所有Linux版本（包括静态版本）"
	@echo "  build-all-linux-script 使用脚本构建所有Linux版本"
	@echo "  build-all-script     使用脚本构建所有平台版本"
	@echo "  build-versions       构建所有版本 (别名)"
	@echo "  build-version        构建特定版本 (需要设置 GOOS 和 GOARCH)"
	@echo ""
	@echo "Docker 命令:"
	@echo "  docker               构建单架构 Docker 镜像"
	@echo "  docker-platforms     构建多平台 Docker 镜像（新方案）"
	@echo "  docker-multiarch     构建多架构 Docker 镜像（旧方案）"
	@echo "  docker-build         构建所有平台镜像"
	@echo "  docker-manifest      创建多架构清单"
	@echo "  docker-unified       创建统一的插件镜像"
	@echo "  docker-verify        验证 Docker 镜像"
	@echo "  docker-push          推送 Docker 镜像"
	@echo "  docker-clean         清理 Docker 镜像"
	@echo "  docker-rebuild       清理并重新构建"
	@echo ""
	@echo "部署命令:"
	@echo "  deploy-local         部署到本地"
	@echo "  deploy-test          部署测试环境"
	@echo "  stop                 停止服务"
	@echo "  status               查看服务状态"
	@echo "  logs                 查看服务日志"
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
	@echo "  make build-static    # 构建静态链接版本"
	@echo "  make test-all        # 完整测试"
	@echo "  make release         # 创建发布版本"
	@echo "  make build-version GOOS=linux GOARCH=arm64  # 构建特定版本"
	@echo "  make build-all-linux # 构建所有Linux版本"
	@echo "  make build-all-script # 使用脚本构建所有平台"
	@echo "  make docker-multiarch # 构建多架构Docker镜像"

# 设置默认目标