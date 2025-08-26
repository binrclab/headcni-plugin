#!/usr/bin/env bash
set -ex

cd $(dirname $0)/..

# 设置默认值
PROG=${PROG:-headcni}
OUTPUT_DIR=${OUTPUT_DIR:-.}
GO_GCFLAGS=${GO_GCFLAGS:-}
GO_BUILD_FLAGS=${GO_BUILD_FLAGS:-}
GO_TAGS=${GO_TAGS:-}

# 版本信息
VERSION=${VERSION:-$(git describe --tags --dirty --always 2>/dev/null || echo "dev")}
COMMIT=${COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo "dev")}
BUILD_DATE=${BUILD_DATE:-$(date -u '+%Y-%m-%d_%H:%M:%S')}

# 调试标志
if [ -z "${GODEBUG}" ]; then
    EXTRA_LDFLAGS="${EXTRA_LDFLAGS} -w"
    DEBUG_GO_GCFLAGS=""
    DEBUG_TAGS=""
else
    DEBUG_GO_GCFLAGS='-gcflags=all=-N -l'
    DEBUG_TAGS="debug"
fi

# 构建标签
BUILDTAGS="netgo osusergo no_stage static_build"
GO_BUILDTAGS="${GO_BUILDTAGS} ${BUILDTAGS} ${DEBUG_TAGS}"
PKG="github.com/binrclab/headcni-plugin"

# 版本标志
VERSION_FLAGS="
    -X main.Version=${VERSION}
    -X main.Commit=${COMMIT:0:8}
    -X main.Program=${PROG}
    -X main.buildDate=${BUILD_DATE}
"

# 静态链接标志
STATIC_FLAGS='-extldflags "-static"'
GO_LDFLAGS="${STATIC_FLAGS} ${EXTRA_LDFLAGS}"

# CGO设置 - 只在amd64上启用
if [ ${GOARCH} = "amd64" ]; then
    CGO_ENABLED="1"
    echo "Building with CGO enabled for ${GOARCH}"
else
    CGO_ENABLED="0"
    echo "Building without CGO for ${GOARCH}"
fi

echo "Building ${PROG} for ${GOOS} in ${GOARCH}"
echo "CGO_ENABLED: ${CGO_ENABLED}"
echo "Build tags: ${GO_BUILDTAGS}"
echo "Debug flags: ${DEBUG_GO_GCFLAGS}"

# 创建输出目录
mkdir -p ${OUTPUT_DIR}

# 根据操作系统构建
if [ "${GOOS}" = "linux" ]; then
    CGO_ENABLED=${CGO_ENABLED} go build \
        -tags "${GO_BUILDTAGS}" \
        ${GO_GCFLAGS} ${GO_BUILD_FLAGS} \
        -o ${OUTPUT_DIR}/${PROG}-linux-${GOARCH} \
        -ldflags "${GO_LDFLAGS} ${VERSION_FLAGS}" \
        ${GO_TAGS}
elif [ "${GOOS}" = "windows" ]; then
    CGO_ENABLED=${CGO_ENABLED} go build \
        -tags "${GO_BUILDTAGS}" \
        ${GO_GCFLAGS} ${GO_BUILD_FLAGS} \
        -o ${OUTPUT_DIR}/${PROG}-windows-${GOARCH}.exe \
        -ldflags "${VERSION_FLAGS} ${GO_LDFLAGS}" \
        ${GO_TAGS}
elif [ "${GOOS}" = "darwin" ]; then
    CGO_ENABLED=${CGO_ENABLED} go build \
        -tags "${GO_BUILDTAGS}" \
        ${GO_GCFLAGS} ${GO_BUILD_FLAGS} \
        -o ${OUTPUT_DIR}/${PROG}-darwin-${GOARCH} \
        -ldflags "${GO_LDFLAGS} ${VERSION_FLAGS}" \
        ${GO_TAGS}
else 
    echo "GOOS:${GOOS} is not yet supported"
    echo "Please file a new GitHub issue requesting support for GOOS:${GOOS}"
    echo "https://github.com/binrclab/headcni-plugin/issues"
    exit 1
fi

echo "Successfully built ${PROG} for ${GOOS}/${GOARCH}"
if [ "${GOOS}" = "linux" ]; then
    ls -la ${OUTPUT_DIR}/${PROG}-linux-${GOARCH}
elif [ "${GOOS}" = "windows" ]; then
    ls -la ${OUTPUT_DIR}/${PROG}-windows-${GOARCH}.exe
elif [ "${GOOS}" = "darwin" ]; then
    ls -la ${OUTPUT_DIR}/${PROG}-darwin-${GOARCH}
fi 