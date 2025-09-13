# macOS App Development using VSCode

This repository contains my personal scaffold for developing macOS applications. It uses an Xcode project but all development is done in VSCode. It makes a bunch of assumptions about development environment, workflow, app signing, services used (Sentry, Sparkle, GitHub Releases, etc.), etc., so it may not be suitable for your needs.

## Features

- Swift LSP support
- Debugging using CodeLLDB with pretty-printing for console output
- Automated release script (publishes to GitHub Releases, uploads dSYMs to Sentry, etc.)
- And some other things...

## Required Tools

- Xcode (`xcodebuild`, `xcrun`, etc.)
- [xcode-build-server](https://github.com/SolaWing/xcode-build-server)
- [xcbeautify](https://github.com/cpisciotta/xcbeautify)
- [op](https://developer.1password.com/docs/cli/) (used in `/Scripts/release.sh`)
- [jq](https://github.com/jqlang/jq) (used in `/Scripts/release.sh`)
- [create-dmg](https://github.com/create-dmg/create-dmg) (used in `/Scripts/release.sh`)
- [sentry-cli](https://github.com/getsentry/sentry-cli) (used in `/Scripts/release.sh`)
- [gh](https://cli.github.com/) (used in `/Scripts/release.sh`)

## Required VSCode Extensions

- [Swift](https://marketplace.visualstudio.com/items?itemName=swiftlang.swift-vscode)
- [CodeLLDB](https://marketplace.visualstudio.com/items?itemName=vadimcn.vscode-lldb)
- [LLDB DAP](https://marketplace.visualstudio.com/items?itemName=llvm-vs-code-extensions.lldb-dap)

## Initial Setup

- `grep` for "TODO" to find places that need be filled in.
- Create your Xcode project in a subdirectory named `${appName}` and set up your Team, etc.
- Never launch Xcode again :).
