#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="BulingIsland"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
SDK="$(xcrun --show-sdk-path --sdk macosx)"

mkdir -p "$BUILD_DIR"

build_with_swiftpm() {
  swift build -c release
}

build_with_swiftc() {
  echo "SwiftPM 不可用或未安装完整 Xcode，改用 swiftc 编译…"
  # shellcheck disable=SC2046
  swiftc -O \
    -target arm64-apple-macosx13.0 \
    -sdk "$SDK" \
    $(find "$SCRIPT_DIR/Sources" -name '*.swift') \
    -framework SwiftUI -framework AppKit -framework IOKit \
    -o "$BUILD_DIR/$APP_NAME"
}

echo "Building $APP_NAME (release)…"
SPM_OUTPUT_FILE="$(mktemp)"
SPM_EXIT=0
if ! build_with_swiftpm >"$SPM_OUTPUT_FILE" 2>&1; then
  SPM_EXIT=$?
fi
SPM_OUTPUT="$(cat "$SPM_OUTPUT_FILE")"
rm -f "$SPM_OUTPUT_FILE"

if [[ $SPM_EXIT -ne 0 ]]; then
  # IDE 正在写入源码时，SwiftPM 可能报 input file modified；重试一次可恢复。
  if [[ "$SPM_OUTPUT" == *"was modified during the build"* ]]; then
    echo "检测到构建期间文件变更，正在重试一次 SwiftPM 构建…"
    SPM_OUTPUT_FILE="$(mktemp)"
    SPM_EXIT=0
    if ! build_with_swiftpm >"$SPM_OUTPUT_FILE" 2>&1; then
      SPM_EXIT=$?
    fi
    SPM_OUTPUT="$(cat "$SPM_OUTPUT_FILE")"
    rm -f "$SPM_OUTPUT_FILE"
  fi
fi

if [[ $SPM_EXIT -eq 0 ]]; then
  echo "$SPM_OUTPUT"
else
  echo "$SPM_OUTPUT"
  # 有外部包依赖时，不能降级到 swiftc（会缺失模块）。
  if [[ -f "$SCRIPT_DIR/Package.swift" ]] && /usr/bin/grep -q "\.package(" "$SCRIPT_DIR/Package.swift"; then
    echo "错误: SwiftPM 构建失败，且检测到外部 Swift 包依赖，无法降级为纯 swiftc 编译。"
    exit "$SPM_EXIT"
  fi
  build_with_swiftc
fi

if [[ ! -f "$BUILD_DIR/$APP_NAME" ]]; then
  echo "错误: 未生成可执行文件 $BUILD_DIR/$APP_NAME"
  exit 1
fi

echo "Creating app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$SCRIPT_DIR/Sources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

ICON_SRC="$SCRIPT_DIR/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
  echo "提示: 未找到 AppIcon.icns，将使用系统默认图标（可将图标置于仓库根目录 AppIcon.icns）。"
fi

for lang in zh-Hans zh-Hant ja ko fr de es it pt en; do
  mkdir -p "$APP_BUNDLE/Contents/Resources/${lang}.lproj"
done

echo "Signing app bundle (ad-hoc)…"
codesign --force --sign - --identifier "com.buling.island" --deep "$APP_BUNDLE" 2>/dev/null || \
  echo "提示: codesign 失败时可忽略（部分环境无签名证书）。"

echo ""
echo "完成: $APP_BUNDLE"
echo "运行: open \"$APP_BUNDLE\""
