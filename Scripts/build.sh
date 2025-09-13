#!/bin/zsh

# Constants
readonly BUILD_SCHEME="" # TODO: Update
readonly CONFIGURATION="Debug"
readonly DESTINATION="platform=macOS,arch=arm64"

# Paths
readonly SCRIPT_DIR="${0:A:h}"
readonly PROJECT_DIR="${SCRIPT_DIR}/.."
readonly DERIVED_DATA_DIR="${PROJECT_DIR}/DerivedData"
readonly RESULT_BUNDLE_PATH="${DERIVED_DATA_DIR}/${BUILD_SCHEME}.xcresult"

if ! command -v xcbeautify &> /dev/null; then
    print "xcbeautify could not be found."
    exit 1
fi

set -o pipefail
rm -rf "${PROJECT_DIR}/DerivedData/${BUILD_SCHEME}.xcresult"
xcodebuild build \
  -scheme ${BUILD_SCHEME} \
  -configuration "${CONFIGURATION}" \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  -resultBundlePath "${RESULT_BUNDLE_PATH}" \
  | xcbeautify --disable-logging
