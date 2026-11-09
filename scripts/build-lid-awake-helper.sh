#!/bin/sh
set -eu
# Build and sign the minimal closed-lid daemon for the direct-distribution apps (Developer ID and
# the free ad-hoc build). The sandboxed App Store profile never ships it.
helper_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Library/HelperTools"
plist_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Library/LaunchDaemons"
case " ${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-} " in
  *NOTCH_APP_STORE*)
    rm -f "$helper_dir/NotchiumLidAwake" "$plist_dir/com.marcusyu.notchium.lid-awake.plist"
    exit 0 ;;
esac
# The free build's helper verifies its peer by identifier and containing bundle instead of a team
# signature (see LidAwakeIdentity), so it must be compiled with the same profile condition.
free_distribution=NO
case " ${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-} ${OTHER_SWIFT_FLAGS:-} " in
  *NOTCH_FREE_DISTRIBUTION*) free_distribution=YES ;;
esac
set --
if [ "$free_distribution" = YES ]; then set -- -D NOTCH_FREE_DISTRIBUTION; fi
mkdir -p "$helper_dir" "$plist_dir"
for arch in $ARCHS; do
    "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" \
        -swift-version 6 -strict-concurrency=complete -O "$@" \
        -file-prefix-map "$SRCROOT=." \
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
    if [ "$free_distribution" = YES ] || [ "${EXPANDED_CODE_SIGN_IDENTITY:-}" = "-" ]; then
        # Ad-hoc, matching the free release policy: no certificate, timestamp or Hardened Runtime.
        /usr/bin/codesign --force --sign - --timestamp=none \
            --identifier com.marcusyu.notchium.lid-awake "$helper_dir/NotchiumLidAwake"
    else
        timestamp_option="--timestamp=none"
        if [ "$CONFIGURATION" = "Release" ]; then timestamp_option="--timestamp"; fi
        /usr/bin/codesign --force --options runtime "$timestamp_option" \
            --identifier com.marcusyu.notchium.lid-awake \
            --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$helper_dir/NotchiumLidAwake"
    fi
fi
# release.sh builds with signing disabled and seals the helper ad-hoc itself before the app.
