#!/bin/zsh
# FoldArc · 取得 MoltenVK（Vulkan → Metal，Apache-2.0）发布包，供 Azahar 核心的 Vulkan 渲染器使用。
# 用法：zsh Scripts/fetch-moltenvk.sh
# 产物：Third-Party/moltenvk/all/MoltenVK/MoltenVK/dynamic/MoltenVK.xcframework（含 ios-arm64 与 ios-arm64_x86_64-simulator）
# "Embed libretro core" 构建阶段会把对应平台的 MoltenVK.framework 拷进 App 并签名；没有它 App 照常构建、核心走软件渲染。
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="v1.4.2"
SHA256="562a15a29bc358446a56a4091c5f7e08f604184187c1d34f712148b61ef17276"
DIR="$PROJECT_DIR/Third-Party/moltenvk"
mkdir -p "$DIR"; cd "$DIR"
if [ ! -f MoltenVK-all.tar ]; then
  curl -fL --retry 3 -o MoltenVK-all.tar "https://github.com/KhronosGroup/MoltenVK/releases/download/$VERSION/MoltenVK-all.tar"
fi
echo "$SHA256  MoltenVK-all.tar" | shasum -a 256 -c -
rm -rf all && mkdir all && tar -xf MoltenVK-all.tar -C all
ls all/MoltenVK/MoltenVK/dynamic/MoltenVK.xcframework
echo "MoltenVK $VERSION ready"
