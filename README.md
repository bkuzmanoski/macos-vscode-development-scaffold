# macOS App Development using VSCode

This repository contains my VSCode scaffold for developing macOS applications. It uses an Xcode project for bundling but all development is done in VSCode. It makes a bunch of assumptions about development environment, workflow, app signing, services used, etc., so it may not be suitable for your needs.

## Features

- Swift LSP support
- Debugging using LLDB with pretty-printing for console output
- Xcode project creation, editing and formatting from the command line (`xcrun xcodeproj`, `xcrun xcprojformatter`)
- Version numbers kept in `Config/Version.xcconfig`
- Automated release script (publishes to GitHub Releases, uploads dSYMs to Sentry, etc.)
- And some other things...

## Required Tools

- Xcode 27.2 or later (`xcodebuild`, `xcrun`, etc.)
- [xcode-build-server](https://github.com/SolaWing/xcode-build-server)
- [xcbeautify](https://github.com/cpisciotta/xcbeautify)
- [op](https://developer.1password.com/docs/cli/) (used in `/Scripts/release.sh`)
- [jq](https://github.com/jqlang/jq) (used in `/Scripts/release.sh`)
- [create-dmg](https://github.com/create-dmg/create-dmg) (used in `/Scripts/release.sh`)
- [sentry-cli](https://github.com/getsentry/sentry-cli) (used in `/Scripts/release.sh`)
- [gh](https://cli.github.com/) (used in `/Scripts/release.sh`)

## Required VSCode Extensions

- [Swift](https://marketplace.visualstudio.com/items?itemName=swiftlang.swift-vscode)
- [LLDB DAP](https://marketplace.visualstudio.com/items?itemName=llvm-vs-code-extensions.lldb-dap)

## Initial Setup

Set up either a new project or an existing one, then follow the steps under [All Projects](#all-projects).

### New Project

Run:

```sh
Scripts/new_project.sh <AppName> <bundle_identifier> <deployment_target> [development_team]
```

This creates `<AppName>.xcodeproj`, a `<AppName>/` source folder, and `Config/*.xcconfig`, fills in the app name, bundle identifier, scheme and team in the scripts and `.vscode/settings.json`, and checks that the build settings resolve.

### Existing Project

1. Convert the project to the JSON project format:

   ```sh
   xcodebuild -project <AppName>.xcodeproj -convert-project xcproj
   ```

2. Create `Config/Version.xcconfig` (with `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`) and `Config/Project.xcconfig` (which must `#include "Version.xcconfig"`).
3. Link `Config/Project.xcconfig` as the project's base configuration:

   ```sh
   xcrun xcodeproj group add Config
   xcrun xcodeproj group add-file Project.xcconfig --group /Config
   xcrun xcodeproj config set Project.xcconfig --group /Config
   ```

4. Remove the version settings from the project file, as they override `Config/Version.xcconfig` (drop `--target` for any that are also set at project level):

   ```sh
   xcrun xcodeproj setting unset MARKETING_VERSION --target <AppName>
   xcrun xcodeproj setting unset CURRENT_PROJECT_VERSION --target <AppName>
   ```

5. `grep` for "TODO" and fill in the app name, bundle identifier, scheme and team in `Scripts/build.sh`, `Scripts/release.sh` and `.vscode/settings.json`.

### All Projects

- Enable the pre-commit hook, which lints staged Swift files and checks project file formatting: `git config core.hooksPath .githooks`
- Before your first release, `grep` for "TODO" in `Scripts/release.sh` and fill in the remaining release settings (secrets, signing identity, Sentry, GitHub and DMG layout).
- Never launch Xcode again :).

## Editing the Project

Use `xcrun xcodeproj` (run `xcrun xcodeproj help <command>` for usage) and run the "Format Project" task afterwards. The "Lint Project" task (also run by the pre-commit hook) shows a diff of any formatting changes.
