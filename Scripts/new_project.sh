#!/bin/zsh

set -e -o pipefail

if (($# < 3)); then
  print -u2 "Usage: ${0:t} <app_name> <bundle_identifier> <deployment_target> [development_team]"
  exit 1
fi

readonly APP_NAME="$1"
readonly BUNDLE_IDENTIFIER="$2"
readonly DEPLOYMENT_TARGET="$3"
readonly DEVELOPMENT_TEAM="${4:-}"

# =============================================================================
# Configuration
# =============================================================================

# Constants
readonly SWIFT_VERSION="6.4"
readonly INITIAL_MARKETING_VERSION="1.0.0"
readonly INITIAL_PROJECT_VERSION="1"

# Paths
readonly SCRIPT_DIR="${0:A:h}"
readonly PROJECT_DIR="${SCRIPT_DIR:h}"
readonly XCODE_PROJECT_NAME="${APP_NAME}.xcodeproj"
readonly SOURCES_DIR_NAME="${APP_NAME}"
readonly CONFIG_DIR_NAME="Config"
readonly PROJECT_XCCONFIG_PATH="${CONFIG_DIR_NAME}/Project.xcconfig"
readonly VERSION_XCCONFIG_PATH="${CONFIG_DIR_NAME}/Version.xcconfig"

# Dependencies
readonly -a REQUIRED_COMMANDS=("xcodebuild" "xcrun" "jq")
readonly -a REQUIRED_XCODE_TOOLS=("xcodeproj" "xcprojformatter")

# =============================================================================
# New Project Script
# =============================================================================

for command in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "${command}" &>/dev/null; then
    print -u2 "${command} could not be found."
    exit 1
  fi
done

for xcode_tool in "${REQUIRED_XCODE_TOOLS[@]}"; do
  if ! xcrun --find "${xcode_tool}" &>/dev/null; then
    print -u2 "${xcode_tool} could not be found (requires Xcode 27.2 or later)."
    exit 1
  fi
done

if [[ ! "${APP_NAME}" =~ ^[A-Za-z][A-Za-z0-9]*$ ]]; then
  print -u2 "Error: App name must start with a letter and contain only letters and digits."
  exit 1
fi

if [[ ! "${BUNDLE_IDENTIFIER}" =~ ^[A-Za-z0-9.-]+$ ]]; then
  print -u2 "Error: Bundle identifier must contain only letters, digits, hyphens and periods."
  exit 1
fi

if [[ ! "${DEVELOPMENT_TEAM}" =~ ^[A-Z0-9]*$ ]]; then
  print -u2 "Error: Development team must contain only uppercase letters and digits."
  exit 1
fi

cd "${PROJECT_DIR}"

for existing_path in "${XCODE_PROJECT_NAME}" "${PROJECT_XCCONFIG_PATH}" "${VERSION_XCCONFIG_PATH}"; do
  if [[ -e "${existing_path}" ]]; then
    print -u2 "Error: ${existing_path} already exists."
    exit 1
  fi
done

export XCODEPROJ_PROJECT="${XCODE_PROJECT_NAME}"

function xcodeproj() {
  print -P "%F{8}xcodeproj ${(q)*}%f"
  xcrun xcodeproj "$@"
}

# Replaces the line matching <pattern> (which must start with a capture group for its indentation) with <replacement>.
# Lines that no longer match (e.g. already filled in) are left unchanged.
function fill_placeholder() {
  local -r file_path="$1"
  local -r pattern="$2"
  local -r replacement="$3"
  local -a lines=("${(@f)$(<"${file_path}")}")
  local -i found=0

  for ((i = 1; i <= ${#lines[@]}; i++)); do
    if [[ "${lines[i]}" =~ ${pattern} ]]; then
      lines[i]="${match[1]}${replacement}"
      found=1
    fi
  done

  if ((found)); then
    print -rl -- "${lines[@]}" >"${file_path}"
    print "✓ ${file_path}: ${replacement}"
  else
    print "– ${file_path}: ${replacement%%=*} already set, skipped"
  fi
}

# Files on disk ---------------------------------------------------------------

mkdir -p "${SOURCES_DIR_NAME}" "${CONFIG_DIR_NAME}"

command cat >"${VERSION_XCCONFIG_PATH}" <<-EOF
	// Updated by Scripts/bump_version.sh. Must not be overridden in the project or target build settings.
	MARKETING_VERSION = ${INITIAL_MARKETING_VERSION}
	CURRENT_PROJECT_VERSION = ${INITIAL_PROJECT_VERSION}
EOF

command cat >"${PROJECT_XCCONFIG_PATH}" <<-EOF
	// Project-level build settings shared by all targets.
	// Target-specific settings are set with \`xcrun xcodeproj setting set <key> <value> --target <target>\`.

	#include "Version.xcconfig"

	SDKROOT = macosx
	MACOSX_DEPLOYMENT_TARGET = ${DEPLOYMENT_TARGET}
	SWIFT_VERSION = ${SWIFT_VERSION}

	CODE_SIGN_STYLE = Automatic
	DEVELOPMENT_TEAM = ${DEVELOPMENT_TEAM}
	ENABLE_HARDENED_RUNTIME = YES

	ALWAYS_SEARCH_USER_PATHS = NO
	DEAD_CODE_STRIPPING = YES
	ENABLE_USER_SCRIPT_SANDBOXING = YES

	ONLY_ACTIVE_ARCH[config=Debug] = YES
	ENABLE_TESTABILITY[config=Debug] = YES
	SWIFT_OPTIMIZATION_LEVEL[config=Debug] = -Onone
	SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Debug] = DEBUG \$(inherited)
	DEBUG_INFORMATION_FORMAT[config=Debug] = dwarf

	// dSYMs are required for Sentry symbolication (see Scripts/release.sh)
	DEBUG_INFORMATION_FORMAT[config=Release] = dwarf-with-dsym
EOF

readonly app_source_path="${SOURCES_DIR_NAME}/${APP_NAME}App.swift"

if [[ ! -e "${app_source_path}" ]]; then
  command cat >"${app_source_path}" <<-EOF
		import SwiftUI

		@main
		struct ${APP_NAME}App: App {
		  var body: some Scene {
		    WindowGroup {
		      Text("Hello, world!")
		    }
		  }
		}
	EOF
fi

# Xcode project ---------------------------------------------------------------

xcodeproj init "${XCODE_PROJECT_NAME}"

xcodeproj target add "${APP_NAME}" --product-type application

# Build phases must exist before the synchronized group is included, otherwise all of its files are excluded
xcodeproj target phase add sources --target "${APP_NAME}"
xcodeproj target phase add frameworks --target "${APP_NAME}"
xcodeproj target phase add resources --target "${APP_NAME}"

xcodeproj group add "${SOURCES_DIR_NAME}" --filesystem-path "${SOURCES_DIR_NAME}"
xcodeproj group include --group "/${SOURCES_DIR_NAME}" --target "${APP_NAME}"

# xcconfig files must be in a regular (non-synchronized) group to be used as a base configuration. File paths are
# relative to the group's folder.
xcodeproj group add "${CONFIG_DIR_NAME}"
xcodeproj group add-file "${PROJECT_XCCONFIG_PATH:t}" --group "/${CONFIG_DIR_NAME}"
xcodeproj config set "${PROJECT_XCCONFIG_PATH:t}" --group "/${CONFIG_DIR_NAME}"

xcodeproj setting set PRODUCT_BUNDLE_IDENTIFIER "${BUNDLE_IDENTIFIER}" --target "${APP_NAME}"

xcrun xcprojformatter --update "${XCODE_PROJECT_NAME}"

# Scaffold placeholders -------------------------------------------------------

print "\nFilling in scaffold placeholders..."

readonly TODO_SUFFIX_PATTERN='[[:space:]]*# TODO: Update$'

fill_placeholder "Scripts/build.sh" \
  "^()readonly BUILD_SCHEME=\"\"${TODO_SUFFIX_PATTERN}" \
  "readonly BUILD_SCHEME=\"${APP_NAME}\""
fill_placeholder "Scripts/release.sh" \
  "^()readonly XCODE_PROJECT_PATH=\"\\\$\{PROJECT_DIR\}/<AppName>\.xcodeproj\"${TODO_SUFFIX_PATTERN}" \
  "readonly XCODE_PROJECT_PATH=\"\${PROJECT_DIR}/${XCODE_PROJECT_NAME}\""
fill_placeholder "Scripts/release.sh" \
  "^()readonly BUILD_SCHEME=\"\"${TODO_SUFFIX_PATTERN}" \
  "readonly BUILD_SCHEME=\"${APP_NAME}\""
fill_placeholder "Scripts/release.sh" \
  "^()readonly DMG_FILENAME=\"<AppName>\.dmg\"${TODO_SUFFIX_PATTERN}" \
  "readonly DMG_FILENAME=\"${APP_NAME}.dmg\""

if [[ -n "${DEVELOPMENT_TEAM}" ]]; then
  fill_placeholder "Scripts/release.sh" \
    "^()readonly DEVELOPMENT_TEAM=\"\"${TODO_SUFFIX_PATTERN}" \
    "readonly DEVELOPMENT_TEAM=\"${DEVELOPMENT_TEAM}\""
fi

fill_placeholder ".vscode/settings.json" \
  '^([[:space:]]*)"appName": "AppName",[[:space:]]*// TODO:.*$' \
  "\"appName\": \"${APP_NAME}\","
fill_placeholder ".vscode/settings.json" \
  '^([[:space:]]*)"bundleIdentifier": "com\.example\.AppName",[[:space:]]*// TODO:.*$' \
  "\"bundleIdentifier\": \"${BUNDLE_IDENTIFIER}\","

# Verification ----------------------------------------------------------------

print "\nVerifying resolved build settings..."

typeset -A expected_build_settings=(
  [PRODUCT_BUNDLE_IDENTIFIER]="${BUNDLE_IDENTIFIER}"
  [MACOSX_DEPLOYMENT_TARGET]="${DEPLOYMENT_TARGET}"
  [SWIFT_VERSION]="${SWIFT_VERSION}"
  [MARKETING_VERSION]="${INITIAL_MARKETING_VERSION}"
  [CURRENT_PROJECT_VERSION]="${INITIAL_PROJECT_VERSION}"
)

typeset build_settings_json

if ! build_settings_json="$(
  xcodebuild \
    -project "${XCODE_PROJECT_NAME}" \
    -target "${APP_NAME}" \
    -showBuildSettings \
    -json \
    2>/dev/null
)"; then
  print -u2 "Project created, but its build settings could not be read. Run 'xcodebuild -project ${XCODE_PROJECT_NAME} -showBuildSettings' for details."
  exit 1
fi

typeset -i mismatch_count=0
typeset actual_value

for setting in ${(ko)expected_build_settings}; do
  actual_value="$(jq --raw-output --arg key "${setting}" '.[0].buildSettings[$key] // ""' <<<"${build_settings_json}")"

  if [[ "${actual_value}" != "${expected_build_settings[$setting]}" ]]; then
    print -u2 "✗ ${setting}: expected '${expected_build_settings[$setting]}', got '${actual_value}'"
    mismatch_count+=1
  else
    print "✓ ${setting}: ${actual_value}"
  fi
done

if ((mismatch_count > 0)); then
  print -u2 "\nProject created, but one or more build settings did not resolve as expected."
  exit 1
fi

print "\nCreated ${XCODE_PROJECT_NAME}."

if [[ -z "${DEVELOPMENT_TEAM}" ]]; then
  print "Set DEVELOPMENT_TEAM in ${PROJECT_XCCONFIG_PATH} and Scripts/release.sh to sign the app with your Apple Developer team."
fi

print "\nUpdate the remaining TODOs in Scripts/release.sh before releasing."
