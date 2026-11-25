#!/bin/zsh
# FoldArc · 第一步：把 Azahar 3DS 核心编成 iPhone (arm64) 静态库。
# 参数与 Azahar 官方 iOS libretro CI（.github/workflows/libretro.yml，runs-on macos-26）一致，
# 只是目标换成核心库，供 FoldArc 自己的 shim 链接。首次运行会克隆源码（含子模块，约 1–2 GB）。
#
# 用法：zsh Scripts/build-azahar-ios.sh [tag]      默认 tag=2126.1.1
#       PLATFORM=iphonesimulator zsh Scripts/build-azahar-ios.sh   （模拟器 arm64 版，产物目录加 -sim）
# 产物：Third-Party/azahar-build-ios[-sim]/bin/Release/azahar_libretro.dylib 与 **/*.a ；日志：同目录 build.log
# 需要：Xcode 27.1、Homebrew 的 cmake（建议再装 ninja）。不需要 ROM、密钥或系统文件。
# 克隆后会按顺序应用 Scripts/patches/azahar/*.patch（已应用的自动跳过）。
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-2126.1.1}"
PLATFORM="${PLATFORM:-iphoneos}"
THIRD="$PROJECT_DIR/Third-Party"
SRC="$THIRD/azahar"
if [ "$PLATFORM" = "iphonesimulator" ]; then BUILD="$THIRD/azahar-build-ios-sim"; else BUILD="$THIRD/azahar-build-ios"; fi
mkdir -p "$THIRD"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

echo "== toolchain"
xcodebuild -version
command -v cmake >/dev/null || { echo "缺少 cmake：请先 brew install cmake ninja"; exit 2; }
cmake --version | head -1
GEN=()
if command -v ninja >/dev/null; then GEN=(-G Ninja); echo "generator: Ninja"; else echo "generator: Unix Makefiles（装 ninja 会快很多）"; fi

echo "== source"
if [ ! -d "$SRC/.git" ]; then
  git clone --depth 1 --branch "$TAG" --recursive https://github.com/azahar-emu/azahar.git "$SRC"
else
  echo "已存在 $SRC（$(git -C "$SRC" describe --tags --always)）"
fi

echo "== patches（FoldArc 对 Azahar 的修改，见 Scripts/patches/azahar/README.md）"
for patch in "$PROJECT_DIR"/Scripts/patches/azahar/*.patch(N); do
  name="${patch:t}"
  if git -C "$SRC" apply --reverse --check "$patch" 2>/dev/null; then
    echo "已应用 $name"
  else
    git -C "$SRC" apply "$patch" && echo "应用 $name"
  fi
done

echo "== configure"
mkdir -p "$BUILD"
cmake -S "$SRC" -B "$BUILD" "${GEN[@]}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$PLATFORM" -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DIOS=ON -DCMAKE_C_FLAGS=-DIOS -DCMAKE_CXX_FLAGS=-DIOS \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCITRA_USE_PRECOMPILED_HEADERS=OFF -DENABLE_OPT=OFF \
  -DENABLE_LIBRETRO=ON \
  -DENABLE_QT=OFF -DENABLE_SDL2=OFF -DENABLE_WEB_SERVICE=OFF -DENABLE_ROOM=OFF -DENABLE_TESTS=OFF \
  -DENABLE_OPENGL=OFF -DENABLE_VULKAN=ON \
  2>&1 | tee "$BUILD/configure.log"

echo "== build（首次 20–60 分钟）"
cmake --build "$BUILD" --target citra_libretro --config Release -j"$(sysctl -n hw.ncpu)" 2>&1 | tee "$BUILD/build.log"

echo "== 产物"
find "$BUILD" -name '*.a' -size +100k | sed "s#$BUILD/##" | sort
ls -la "$BUILD"/bin/Release/*.dylib 2>/dev/null || true
echo "DONE"
