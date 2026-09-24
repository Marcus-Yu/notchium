#!/bin/sh
set -eu
# Build and sign a minimal daemon in the direct-distribution app only.
helper_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Library/HelperTools"
plist_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Library/LaunchDaemons"
case " ${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-} " in
  *NOTCH_APP_STORE*)
    rm -f "$helper_dir/NotchiumLidAwake" "$plist_dir/com.marcusyu.notchium.lid-awake.plist"
    exit 0 ;;
esac
mkdir -p "$helper_dir" "$plist_dir"
for arch in $ARCHS; do
    "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" \
        -swift-version 6 -strict-concurrency=complete -O \
        -sdk "$SDKROOT" -target "$arch-apple-macosx$MACOSX_DEPLOYMENT_TARGET" \
        "$SRCROOT/NotchiumPackage/Sources/NotchiumServices/LidAwakeProtocol.swift" \
        "$SRCROOT/Helpers/LidAwake/PowerOverride.swift" \
        "$SRCROOT/Helpers/LidAwake/main.swift" \
        -o "$DERIVED_FILE_DIR/NotchiumLidAwake-$arch"
done
# Xcode supplies ARCHS; paths remain separate quoted arguments.
set --
for arch in $ARCHS; do set -- "$@" "$DERIVED_FILE_DIR/NotchiumLidAwake-$arch"; done
"$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/lipo" -create "$@" -output "$helper_dir/NotchiumLidAwake"
/usr/bin/install -m 644 "$SRCROOT/Helpers/LidAwake/com.marcusyu.notchium.lid-awake.plist" "$plist_dir/"
if [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]; then
    timestamp_option="--timestamp=none"
    if [ "$CONFIGURATION" = "Release" ]; then timestamp_option="--timestamp"; fi
    /usr/bin/codesign --force --options runtime "$timestamp_option" \
        --identifier com.marcusyu.notchium.lid-awake \
        --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$helper_dir/NotchiumLidAwake"
fi
