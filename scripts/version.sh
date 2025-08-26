#!/usr/bin/env bash

# 获取版本信息
VERSION=${VERSION:-$(git describe --tags --dirty --always 2>/dev/null || echo "dev")}
COMMIT=${COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo "dev")}
BUILD_DATE=${BUILD_DATE:-$(date -u '+%Y-%m-%d_%H:%M:%S')}

# 导出变量
export VERSION
export COMMIT
export BUILD_DATE

# 显示版本信息
echo "Version: ${VERSION}"
echo "Commit: ${COMMIT}"
echo "Build Date: ${BUILD_DATE}" 