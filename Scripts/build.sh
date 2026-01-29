#!/bin/zsh

set -o pipefail

# =============================================================================
# Configuration
# =============================================================================

# Constants
readonly BUILD_SCHEME="" # TODO: Update
readonly BUILD_CONFIGURATION="Debug"
readonly DESTINATION="platform=macOS,arch=arm64"

# Paths
readonly SCRIPT_DIR="${0:A:h}"
readonly PROJECT_DIR="${SCRIPT_DIR}/.."
readonly DERIVED_DATA_DIR="${PROJECT_DIR}/DerivedData"
readonly BUILD_LOG_PATH="${DERIVED_DATA_DIR}/xcodebuild.log"

# Dependencies
readonly -a REQUIRED_COMMANDS=("xcodebuild" "xcbeautify" "xcode-build-server")

# =============================================================================
# Build Script
# =============================================================================

for command in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "${command}" &>/dev/null; then
    print "${command} could not be found."
    exit 1
  fi
done

function update_compilation_flags() {
  cd "${PROJECT_DIR}"
  xcode-build-server parse -a "${BUILD_LOG_PATH}"
}

trap '
  update_compilation_flags
  print "\n$(date +"%Y-%m-%d %H:%M:%S")"
' EXIT

mkdir -p "${BUILD_LOG_PATH:A:h}"

if [ -f "${BUILD_LOG_PATH}" ]; then
  rm -rf "${BUILD_LOG_PATH}"
fi

xcodebuild build \
  -scheme "${BUILD_SCHEME}" \
  -configuration "${BUILD_CONFIGURATION}" \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  | tee "${BUILD_LOG_PATH}" \
  | xcbeautify --disable-logging
