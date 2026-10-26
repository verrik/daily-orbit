#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${ORBIT_BUILD_DIR:-$SOURCE_DIR/.build}"
mkdir -p "$BUILD_DIR/module-cache" "$BUILD_DIR/tests"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
export SWIFT_MODULECACHE_PATH="$BUILD_DIR/module-cache"
swiftc -swift-version 5 -parse-as-library "$SOURCE_DIR/Sources/APODCore.swift" "$SOURCE_DIR/Tests/CoreTests.swift" \
    -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers -o "$BUILD_DIR/CoreTests"
"$BUILD_DIR/CoreTests" "$BUILD_DIR/tests"
