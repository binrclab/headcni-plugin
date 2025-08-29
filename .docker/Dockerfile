# Build Stage - 使用目标架构的基础镜像
FROM golang:1.24-alpine AS builder

# Declare build arguments
ARG TARGETOS
ARG TARGETARCH
ARG GOPROXY=https://goproxy.cn,direct
ARG GOSUMDB=sum.golang.google.cn

# 使用国内 Alpine 镜像源并安装构建依赖（静态链接不需要 gcc 和 musl-dev）
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories && \
    apk update && \
    apk add --no-cache --virtual .build-deps \
        git \
        make \
        curl \
        ca-certificates \
        bash \
    && rm -rf /var/cache/apk/*

# Set Go proxy
ENV GOPROXY=$GOPROXY
ENV GOSUMDB=$GOSUMDB

# Set working directory
WORKDIR /app

# Copy go mod files first for better caching
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

    # 构建目标架构的二进制文件（静态链接，不依赖系统动态库）
# 修复后的构建命令
RUN set -eux; \
    TARGETARCH=${TARGETARCH:-amd64}; \
    BUILD_DATE=$(date -u '+%Y-%m-%dT%H:%M:%SZ'); \
    VERSION=${VERSION:-"1.0.0"}; \
    COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown'); \
    mkdir -p /app/bin; \
    \
    case "$TARGETARCH" in \
        amd64|arm64) OS_LIST="linux windows darwin"; ;; \
        *) OS_LIST="linux"; ;; \
    esac; \
    \
    for os in $OS_LIST; do \
        echo "Building $os/$TARGETARCH"; \
        CGO_ENABLED=0 GOOS="$os" GOARCH="$TARGETARCH" go build \
            -ldflags "-X main.Version=$VERSION -X main.Commit=$COMMIT -X main.buildDate=$BUILD_DATE -s -w" \
            -o "/app/bin/headcni-$os-$TARGETARCH$([ "$os" = "windows" ] && echo .exe || echo '')" \
            .; \
    done

# Runtime Stage - 使用兼容的基础镜像
FROM alpine:3.19

# Add metadata labels
LABEL maintainer="binrc <support@binrc.com>"
LABEL org.opencontainers.image.title="HeadCNI Plugin"
LABEL org.opencontainers.image.description="CNI Plugin binary for specific platform"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.vendor="binrc"
LABEL org.opencontainers.image.source="https://github.com/binrc/headcni-plugin"

# Set working directory
WORKDIR /app

# Define build arguments for platform
ARG TARGETOS
ARG TARGETARCH

# Copy the binary from the builder stage
COPY --from=builder /app/bin/headcni-* /app/

# Verify the binary exists and show what we have
RUN echo "Available binaries:" && ls -la /app/headcni* && \
    if [ ! -f /app/headcni* ]; then \
        echo "Error: No binary found for $TARGETOS-$TARGETARCH"; \
        exit 1; \
    fi

# Copy the installation script
COPY .docker/entrypoint.sh /entrypoint.sh

RUN chmod +x /app/headcni* /entrypoint.sh && \
    echo "Built for platform: $TARGETOS-$TARGETARCH" && ls -la /app/

# 设置默认的复制目标目录（根据平台动态设置）
ENV CNI_BIN_NAME="headcni"

# Set the entrypoint and default command
ENTRYPOINT ["/entrypoint.sh"]
CMD ["install"]