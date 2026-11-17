# Contributing

Please open an issue before starting a substantial change. Describe the expected behavior, actual behavior, macOS version, and steps to reproduce. Remove public IP addresses and other personal information from logs before posting them.

Use English for source comments, documentation, issues, and pull requests. Keep interface translations in the localization resources.

Run `swift build` and `./scripts/test.sh` before submitting changes. For UI changes, run `swift run IPWidgetSnapshot` and inspect the generated images. For packaging changes, run `./scripts/make-installer.sh` on an Apple Silicon Mac with a compatible macOS SDK.

Pull requests should explain the behavior changed and the validation performed. Do not commit generated apps, packages, local notes, credentials, or build caches. Preserve the DB-IP attribution when changing country data.

## Command Line Tools 6.4 test workaround

If the default test command cannot load `TestingMacros`, use the native SwiftPM build system and the CLT framework/plugin paths. For the standard CLT installation:

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/ipwidget-clang-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/ipwidget-swift-cache \
  swift test --disable-sandbox --build-system native \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks
```

This works around local CLT test-runner integration; it does not change production sandbox entitlements. Other toolchains may not need these arguments.
