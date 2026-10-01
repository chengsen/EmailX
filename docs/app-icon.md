# EmailX app icon

The application uses `MyEmail/EmailXAppIcon.icon`, a native Icon Composer package with a charcoal background and separate vector groups for the silver envelope and white flap. Both shapes were redrawn from the existing EmailX icon; the original PNG assets remain in `AppIcon.appiconset` for recovery. Debug and Release select `EmailXAppIcon` as their app icon.

The manifest uses the native structure from Apple's [Landmarks sample](https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass), compiled by the installed Xcode 27 `actool`. No sample artwork or additional runtime dependency is included. Icon Composer's license was accepted with user authorization, but its subsequent accessibility observations timed out. Consequently, this package was assembled from the verified native format and validated with Apple's compiler rather than saved through the Composer UI.

The asset compiler generates `EmailXAppIcon.icns` and `Assets.car`; the latter contains separate envelope and flap vector assets, icon groups, an icon stack, and Aqua, Dark Aqua and tintable appearances. The generated ICNS preview was inspected to verify that the flap remains visible above the envelope. Actual Dock rendering across system appearance settings still requires runtime inspection.

To verify the resource without compiling application source:

```sh
mkdir -p build/IconVerification/Combined
xcrun actool MyEmail/Assets.xcassets MyEmail/EmailXAppIcon.icon \
  --compile build/IconVerification/Combined \
  --platform macosx --minimum-deployment-target 27.0 \
  --app-icon EmailXAppIcon \
  --output-partial-info-plist build/IconVerification/Combined/asset-info.plist \
  --output-format human-readable-text
xcrun assetutil --info build/IconVerification/Combined/Assets.car
```

A full application build must also select the new icon: its asset compilation inputs should include `EmailXAppIcon.icon`, its resources should contain `EmailXAppIcon.icns`, and `CFBundleIconName` should be `EmailXAppIcon`. To restore the original selection, set `ASSETCATALOG_COMPILER_APPICON_NAME` back to `AppIcon` in both configurations. The vector package does not require rebuilding the PNG size variants; the platform handles sizing and material effects.
