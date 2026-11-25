#!/bin/zsh
# Xcode "Embed libretro core" phase:
#  1. wrap the Azahar libretro core built by Scripts/build-azahar-ios.sh for
#     the current platform as azahar_libretro.framework in the app's
#     Frameworks folder (iOS takes dynamic libraries only inside framework
#     bundles: Apple TN2435), with its Info.plist and privacy manifest;
#  2. copy MoltenVK.framework (Vulkan on Metal, fetched by
#     Scripts/fetch-moltenvk.sh) next to it and add its privacy manifest (the
#     release ships none) — the host dlopens it at run time to give the core's
#     Vulkan renderer a device;
# and sign both with the app's identity. Either one missing = the app still
# builds: no core -> "核心不可用"; no MoltenVK -> the core uses its software
# renderer.
set -eu
DEST_DIR="$BUILT_PRODUCTS_DIR/$FRAMEWORKS_FOLDER_PATH"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] || [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ]; then IDENTITY="-"; fi
MVK_XC="$SRCROOT/Third-Party/moltenvk/all/MoltenVK/MoltenVK/dynamic/MoltenVK.xcframework"
PRIVACY="$SRCROOT/Scripts/privacy"
for manifest in azahar_libretro.xcprivacy MoltenVK.xcprivacy; do
  [ -f "$PRIVACY/$manifest" ] || { echo "error: missing $PRIVACY/$manifest (the embedded bundles must carry their privacy manifests)"; exit 1; }
done
case "${PLATFORM_NAME:-iphoneos}" in
  iphonesimulator)
    SRC="$SRCROOT/Third-Party/azahar-build-ios-sim/bin/Release/azahar_libretro.dylib"
    MVK="$MVK_XC/ios-arm64_x86_64-simulator/MoltenVK.framework"
    PLATFORM_KEY="iPhoneSimulator" ;;
  *)
    SRC="$SRCROOT/Third-Party/azahar-build-ios/bin/Release/azahar_libretro.dylib"
    MVK="$MVK_XC/ios-arm64/MoltenVK.framework"
    PLATFORM_KEY="iPhoneOS" ;;
esac
mkdir -p "$DEST_DIR"
# Builds before the 15th round put the core here as a bare dylib.
rm -f "$DEST_DIR/azahar_libretro.dylib"

FW="$DEST_DIR/azahar_libretro.framework"
if [ -f "$SRC" ]; then
  # Rebuilt every time (a copy of ~28 MB): only the binary, its Info.plist
  # and its privacy manifest go in.
  rm -rf "$FW"
  mkdir -p "$FW"
  cp -f "$SRC" "$FW/azahar_libretro"
  chmod u+w "$FW/azahar_libretro"
  xcrun install_name_tool -id "@rpath/azahar_libretro.framework/azahar_libretro" "$FW/azahar_libretro"
  # The framework's minimum OS must match the binary's (LC_BUILD_VERSION).
  MINOS="$(xcrun vtool -show-build "$FW/azahar_libretro" 2>/dev/null | awk '/minos/ {print $2; exit}')"
  [ -n "$MINOS" ] || MINOS="${IPHONEOS_DEPLOYMENT_TARGET:-17.0}"
  cat > "$FW/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>azahar_libretro</string>
	<key>CFBundleIdentifier</key><string>${PRODUCT_BUNDLE_IDENTIFIER:-com.foldarc.prototype}.azahar-libretro</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>azahar_libretro</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>${MARKETING_VERSION:-1.0}</string>
	<key>CFBundleVersion</key><string>${CURRENT_PROJECT_VERSION:-1}</string>
	<key>CFBundleSupportedPlatforms</key><array><string>${PLATFORM_KEY}</string></array>
	<key>MinimumOSVersion</key><string>${MINOS}</string>
</dict>
</plist>
PLIST
  cp -f "$PRIVACY/azahar_libretro.xcprivacy" "$FW/PrivacyInfo.xcprivacy"
  /usr/bin/codesign --force --sign "$IDENTITY" --timestamp=none "$FW"
  echo "embedded libretro core ($PLATFORM_NAME, minos $MINOS) -> $FW"
else
  rm -rf "$FW"
  echo "warning: libretro core not found for $PLATFORM_NAME at $SRC (run Scripts/build-azahar-ios.sh); app will run without it"
fi

if [ -d "$MVK" ]; then
  /usr/bin/rsync -a --delete "$MVK/" "$DEST_DIR/MoltenVK.framework/"
  chmod -R u+w "$DEST_DIR/MoltenVK.framework"
  cp -f "$PRIVACY/MoltenVK.xcprivacy" "$DEST_DIR/MoltenVK.framework/PrivacyInfo.xcprivacy"
  /usr/bin/codesign --force --sign "$IDENTITY" --timestamp=none "$DEST_DIR/MoltenVK.framework"
  echo "embedded MoltenVK ($PLATFORM_NAME) -> $DEST_DIR/MoltenVK.framework"
else
  echo "warning: MoltenVK not found at $MVK (run Scripts/fetch-moltenvk.sh); the core will use software rendering"
fi
