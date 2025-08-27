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
    RUN mkdir -p /app/bin && \
        set -eux; \
        case "$TARGETARCH" in \
            amd64) OS_LIST="linux windows darwin"; ;; \
            arm64) OS_LIST="linux windows darwin"; ;; \
            386) OS_LIST="linux"; ;; \
            arm/v7) OS_LIST="linux"; ;; \
            arm/v8) OS_LIST="linux"; ;; \
            ppc64le) OS_LIST="linux"; ;; \
            s390x) OS_LIST="linux"; ;; \
            riscv64) OS_LIST="linux"; ;; \
            *) OS_LIST="linux"; ;; \
        esac; \
        for os in $OS_LIST; do \
            # 统一使用静态链接，避免依赖系统的动态库
            CGO_ENABLED=0; \
            echo "Building $os/$TARGETARCH with CGO_ENABLED=$CGO_ENABLED (static linking)"; \
            GOOS="$os" GOARCH="$TARGETARCH" CGO_ENABLED="$CGO_ENABLED" go build -ldflags "-X main.Version=1.0.0 -X main.Commit=$(git rev-parse --short HEAD 2>/dev/null || echo 'dev') -s -w" -o "/app/bin/headcni-$os-$TARGETARCH" .; \
            if [ "$os" = "windows" ]; then \
                cp "/app/bin/headcni-$os-$TARGETARCH" "/app/headcni-$os-$TARGETARCH.exe"; \
            else \
                cp "/app/bin/headcni-$os-$TARGETARCH" "/app/headcni-$os-$TARGETARCH"; \
            fi; \
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
COPY --from=builder /app/headcni-* /app/

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