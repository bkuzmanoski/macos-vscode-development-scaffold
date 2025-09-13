# macOS App Development using VSCode

This repository contains my personal scaffold for developing macOS applications. It uses an Xcode project for building the app, but all development is done in VSCode. It makes a bunch of assumptions about development environment, workflow, app signing, services used (Sentry, Sparkle, etc.), etc., so it may not be suitable for your needs.

## Features

- Swift LSP support
- Debugging using CodeLLDB with pretty-printing for console output
- Automated release script (publishes to GitHub Releases, uploads dSYMs to Sentry, etc.)
- And some other things...

## Required Tools

- [xcode-build-server](https://github.com/SolaWing/xcode-build-server)
- [xcbeautify](https://github.com/cpisciotta/xcbeautify)
- [create-dmg](https://github.com/create-dmg/create-dmg) (used in `/Scripts/release.sh`)
- [sentry-cli](https://github.com/getsentry/sentry-cli) (used in `/Scripts/release.sh`)

## Required VSCode Extensions

- [Swift](https://marketplace.visualstudio.com/items?itemName=swiftlang.swift-vscode)
- [CodeLLDB](https://marketplace.visualstudio.com/items?itemName=vadimcn.vscode-lldb)
- [LLDB DAP](https://marketplace.visualstudio.com/items?itemName=llvm-vs-code-extensions.lldb-dap)

## Initial Setup

- `grep` for "TODO" to find places that need be filled in.
- Create your Xcode project in a subdirectory named `${appName}` and set up your Team, etc.
- Never launch Xcode again :).
