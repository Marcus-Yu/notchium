# App icon

The app target uses `Notchium/Assets.xcassets/AppIcon.appiconset`.
`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` in `Config/Shared.xcconfig`
selects it for both Debug and Release. The catalog belongs to the app through
Xcode's synchronized `Notchium` folder; no manual resource reference is needed.
`ASSETCATALOG_COMPILER_STANDALONE_ICON_BEHAVIOR = all` retains every size in
the compiled `AppIcon.icns`, alongside the complete icon in `Assets.car`.
Xcode supplies the bundle icon metadata. A separate checked-in `.icns` is
unnecessary. See Apple's [app icon guide](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
and [build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference).

The original supplied transparent 360×360 PNG is preserved byte-for-byte at
`artwork/AppIcon-master.png`, outside the app's resource folder.
Regenerate all ten macOS slots with the installed Xcode Swift toolchain:

```sh
swift scripts/generate-app-icon.swift
```

The script uses Apple's CoreGraphics and ImageIO, with no extra dependency.
It reads the master once and renders every size directly from it: 16, 32, 64,
128, 256, 512, and 1024 pixels, assigned to the standard 1x/2x slots.
Filtered reductions preserve readability at small sizes; nearest-neighbor
enlargements preserve the pixel-art edges. Transparency and the source color
space are retained. The larger files do not introduce detail beyond the master.

Build `Notchium.xcworkspace` using the `Notchium` scheme. Validate the built
app's `Contents/Info.plist` icon keys and `Contents/Resources/AppIcon.icns`.
Finder and Applications use those bundle resources. An existing installed copy
must be replaced with the rebuilt app, then quit and relaunch it. If macOS still
shows a cached icon, use Product → Clean Build Folder, rebuild, and reinstall.

macOS also applies the user's **System Settings → Appearance → Icon & widget
style**. Select **Default** to display the original colors; **Clear** and
**Tinted** apply the system's chosen treatment. See Apple's
[appearance guide](https://support.apple.com/en-lamr/guide/macbook-pro/apd2add7474b/2026/mac/26).

Notchium starts as an accessory/menu-bar app (`LSUIElement = YES`). While
Settings is open, it switches to `.regular` activation policy and shows this
app icon in the Dock and app switcher. Closing Settings restores `.accessory`;
minimizing Settings keeps the Dock icon available. All system presentations use
the same bundle resources.
