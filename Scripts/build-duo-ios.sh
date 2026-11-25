#!/bin/zsh
# This opt-in build path requires Xcode 27.1 (iOS 27.1 SDK) or later.
# Signing/installing on a phone still requires your own Apple developer team.
set -eu
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/.build"
if ! xcrun --sdk iphonesimulator --show-sdk-version > "$PROJECT_DIR/.build/ios-sdk-version.txt" 2>/dev/null; then
  echo '需要先安装并选择完整 Xcode 27.1+，当前没有 iOS Simulator SDK。' >&2
  exit 1
fi
SDK_VERSION="$(cat "$PROJECT_DIR/.build/ios-sdk-version.txt")"
SDK_MAJOR="${SDK_VERSION%%.*}"
SDK_REST="${SDK_VERSION#*.}"
SDK_MINOR="${SDK_REST%%.*}"
if (( SDK_MAJOR < 27 || (SDK_MAJOR == 27 && SDK_MINOR < 1) )); then
  echo "当前 SDK 为 $SDK_VERSION；设备折叠接口需要 iOS 27.1+。" >&2
  exit 1
fi
xcodebuild -project "$PROJECT_DIR/FoldArc.xcodeproj" -scheme FoldArc-Duo -configuration DuoSDK \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$PROJECT_DIR/.build/DuoDerivedData" \
  CODE_SIGNING_ALLOWED=NO build
