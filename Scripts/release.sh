#!/bin/zsh

set -u

# =============================================================================
# Configuration
# =============================================================================

# Paths
readonly SCRIPT_DIR="${0:A:h}"
readonly PROJECT_DIR="${SCRIPT_DIR}/.."
readonly RELEASES_DIR="${PROJECT_DIR}/Releases"
readonly ASSETS_DIR="${RELEASES_DIR}/Assets"
readonly TEMP_DIR="${RELEASES_DIR}/Temp"
readonly BUMP_VERSION_SCRIPT_PATH="${SCRIPT_DIR}/bump_version.sh"
readonly COMMAND_OUTPUT_PATH="${TEMP_DIR}/command_output.log"

# 1Password Secrets References
readonly OP_APPLE_ID_REF="op://path/to/secret" # TODO: Update
readonly OP_NOTARYTOOL_PASSWORD_REF="op://path/to/secret" # TODO:  Update
readonly OP_SENTRY_AUTH_TOKEN_REF="op://path/to/secret" # TODO:  Update

# Project Settings
readonly DEVELOPMENT_TEAM="" # TODO: Update
readonly SIGNING_IDENTITY="" # TODO: Update
readonly XCODE_PROJECT_PATH="${PROJECT_DIR}/<AppName>.xcodeproj" # TODO: Update
readonly BUILD_SCHEME="" # TODO: Update
readonly -A RELEASE_CONFIGURATIONS=( # TODO: Update
  # [plugin]=build_configuration|release_repository_dir|release_repository_name
)
readonly PRODUCTION_RELEASE_CONFIGURATION_KEY="" # TODO: Update

# Sentry Settings
readonly SENTRY_ORG="" # TODO: Update
readonly SENTRY_PROJECT="" # TODO: Update

# GitHub Settings
readonly RELEASE_REPOSITORY_OWNER="" # TODO: Update

# DMG Settings
readonly DMG_FILENAME="<AppName>.dmg" # TODO: Update
readonly DMG_BACKGROUND_PATH="${ASSETS_DIR}/DMGBackground.png" # TODO: Update
readonly DMG_WINDOW_POS_X=200 # TODO: Update
readonly DMG_WINDOW_POS_Y=120 # TODO: Update
readonly DMG_WINDOW_WIDTH=640 # TODO: Update
readonly DMG_WINDOW_HEIGHT=540 # TODO: Update
readonly DMG_ICON_SIZE=100 # TODO: Update
readonly DMG_APP_ICON_POS_X=167 # TODO: Update
readonly DMG_APP_ICON_POS_Y=274 # TODO: Update
readonly DMG_APP_DROP_LINK_POS_X=473 # TODO: Update
readonly DMG_APP_DROP_LINK_POS_Y=274 # TODO: Update

# Dependencies
readonly -a REQUIRED_COMMANDS=("${BUMP_VERSION_SCRIPT_PATH}" "op" "xcodebuild" "jq" "xcrun" "create-dmg" "sentry-cli" "gh")
readonly -a REQUIRED_XCODE_TOOLS=("agvtool" "notarytool" "stapler")
readonly -a REQUIRED_PATHS=("${XCODE_PROJECT_PATH}" "${DMG_BACKGROUND_PATH}")
readonly -a REQUIRED_SECRETS=( "${OP_APPLE_ID_REF}" "${OP_NOTARYTOOL_PASSWORD_REF}" "${OP_SENTRY_AUTH_TOKEN_REF}")
readonly -a REQUIRED_BUILD_SETTINGS=("PRODUCT_NAME" "MACOSX_DEPLOYMENT_TARGET" "MARKETING_VERSION" "CURRENT_PROJECT_VERSION")

# =============================================================================
# Utility Functions
# =============================================================================

readonly OUTPUT_PADDING="           "

log_stage() {
  print -P "\n$(date +%H:%M:%S) %B‣ $@%b"
}

log_info() {
  print "${OUTPUT_PADDING}– $@"
}

log_success() {
  print -P "${OUTPUT_PADDING}%F{green}✓ $@%f"
}

log_warning() {
  print -P "${OUTPUT_PADDING}%F{yellow}! $@%f"
}

log_error() {
  print -P "${OUTPUT_PADDING}%F{red}✗ $@%f"
}

log_failure_and_exit() {
  print -P "\n%F{red}%BRelease failed%b%f\n$@"
  exit 1
}

clear_lines() {
  local number_of_lines=${1:-1}

  for ((i=1; i<=number_of_lines; i++)); do
    print -nP '\e[1A\e[2K\r'
  done
}

run_command() {
  local command_description=$1
  shift

  log_info "${command_description}"
  print "[$(date +%H:%M:%S)] $@" >> "${COMMAND_OUTPUT_PATH}"

  local output
  local exit_code=0

  output=$("$@" 2>&1) || exit_code=$?

  print "${output}\n" >> "${COMMAND_OUTPUT_PATH}"

  if [[ ${exit_code} -ne 0 ]]; then
    clear_lines 1
    log_error "${command_description}"
    log_failure_and_exit "Last command failed (${exit_code}).\nDetails: ${COMMAND_OUTPUT_PATH}"
  fi
}

# =============================================================================
# Release Script
# =============================================================================

log_stage "Select release configuration"

typeset -a release_configuration_keys=("${(@ko)RELEASE_CONFIGURATIONS}")
typeset release_configuration_key

for ((i=1; i<=${#release_configuration_keys[@]}; i++)); do
  print "${OUTPUT_PADDING}${i}) ${release_configuration_keys[$i]}"
done

print ""

while true; do
  read "CHOICE?${OUTPUT_PADDING}Enter choice (1-${#release_configuration_keys[@]}): "

  if [[ "${CHOICE}" =~ ^[1-9][0-9]*$ ]] && (( CHOICE >= 1 && CHOICE <= ${#release_configuration_keys[@]} )); then
    release_configuration_key="${release_configuration_keys[$CHOICE]}"
    clear_lines $(( ${#release_configuration_keys[@]} + 2 ))
    log_success "${release_configuration_key}"
    break
  else
    clear_lines 1
  fi
done

typeset -a release_configuration_parts=("${(s:|:)RELEASE_CONFIGURATIONS[$release_configuration_key]}")
typeset build_configuration="${release_configuration_parts[1]}"
typeset release_repository_dir="${release_configuration_parts[2]}"
typeset release_repository_name="${release_configuration_parts[3]}"

if [[ ! -d "${release_repository_dir}" ]]; then
  log_failure_and_exit "Release repository directory does not exist: ${release_repository_dir}"
fi

# -----------------------------------------------------------------------------
log_stage "Select release type"

typeset -a release_type_options=("Major" "Minor" "Patch" "Keep current version")
typeset release_type

for ((i=1; i<=${#release_type_options[@]}; i++)); do
  print "${OUTPUT_PADDING}${i}) ${release_type_options[$i]}"
done

print ""

while true; do
  read "CHOICE?${OUTPUT_PADDING}Enter choice (1-${#release_type_options[@]}): "

  if [[ "${CHOICE}" =~ ^[1-9][0-9]*$ ]] && (( CHOICE >= 1 && CHOICE <= ${#release_type_options[@]} )); then
    release_type="${release_type_options[$CHOICE]}"
    clear_lines $(( ${#release_type_options[@]} + 2 ))
    log_success "${release_type}"
    break
  else
    clear_lines 1
  fi
done

# -----------------------------------------------------------------------------
if [[ "${release_type}" != "Keep current version" ]]; then
  log_stage "Setting app version" "${BUMP_VERSION_SCRIPT_PATH}" "--${release_type:l}" "${XCODE_PROJECT_PATH}"
fi

# -----------------------------------------------------------------------------
log_stage "Checking dependencies"

typeset missing_dependencies=0

for command in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "${command}" &>/dev/null; then
    log_error "${command}"
    missing_dependencies=$((missing_dependencies + 1))
  else
    log_success "${command}"
  fi
done

for xcode_tool in "${REQUIRED_XCODE_TOOLS[@]}"; do
  if ! xcrun --find "${xcode_tool}" &>/dev/null; then
    log_error "${xcode_tool}"
    missing_dependencies=$((missing_dependencies + 1))
  else
    log_success "${xcode_tool}"
  fi
done

for required_path in "${REQUIRED_PATHS[@]}"; do
  if [[ ! -e "${required_path}" ]]; then
    log_error "${required_path}"
    missing_dependencies=$((missing_dependencies + 1))
  else
    log_success "${required_path}"
  fi
done

if [[ ${missing_dependencies} -gt 0 ]]; then
  log_failure_and_exit "One or more dependencies are missing."
fi

# -----------------------------------------------------------------------------
log_stage "Retrieving secrets from 1Password"

typeset -A secrets
typeset -a missing_secrets=()

for secret_ref in "${REQUIRED_SECRETS[@]}"; do
  typeset secret_value=$(op read --no-newline "${secret_ref}" 2>/dev/null)

  if [[ $? -ne 0 || -z "${secret_value}" ]]; then
    log_error "${secret_ref}"
    missing_secrets+=("${secret_ref}")
  else
    log_success "${secret_ref}"
    secrets[$secret_ref]=${secret_value}
  fi
done

if [[ ${#missing_secrets[@]} -gt 0 ]]; then
  log_failure_and_exit "One or more required secrets could not be retrieved."
fi

readonly apple_id=${secrets[${OP_APPLE_ID_REF}]}
readonly notarytool_password=${secrets[${OP_NOTARYTOOL_PASSWORD_REF}]}
readonly sentry_auth_token=${secrets[${OP_SENTRY_AUTH_TOKEN_REF}]}

# -----------------------------------------------------------------------------
log_stage "Reading build settings from Xcode"

typeset -A build_settings=(
  "${(f)"$( \
    xcodebuild \
      -project "${XCODE_PROJECT_PATH}" \
      -scheme "${BUILD_SCHEME}" \
      -configuration "${build_configuration}" \
      -showBuildSettings \
      -json \
      2>/dev/null \
    | jq \
      '.[0].buildSettings as $settings | $ARGS.positional[] | ., $settings[.]' \
      --args "${REQUIRED_BUILD_SETTINGS[@]}" \
      --raw-output \
      2>/dev/null \
  )"}"
)
typeset -a missing_settings=()

for setting in "${REQUIRED_BUILD_SETTINGS[@]}"; do
  if [[ -z "${build_settings[$setting]}" ]]; then
    log_error "${setting}"
    missing_settings+=("${setting}")
  else
    log_success "${setting}: ${build_settings[$setting]}"
  fi
done

if [[ ${#missing_settings[@]} -gt 0 ]]; then
  log_failure_and_exit "One or more required build settings are missing."
fi

readonly product_name=${build_settings[PRODUCT_NAME]}
readonly minimum_system_version=${build_settings[MACOSX_DEPLOYMENT_TARGET]}
readonly version=${build_settings[MARKETING_VERSION]}
readonly build_number=${build_settings[CURRENT_PROJECT_VERSION]}
readonly version_and_build_number="${version} (${build_number})"

# -----------------------------------------------------------------------------
log_stage "Starting release process"

log_info "Development team: ${DEVELOPMENT_TEAM}"
log_info "Signing identity: ${SIGNING_IDENTITY}"
log_info "Xcode project: ${XCODE_PROJECT_PATH}"
log_info "Build scheme: ${BUILD_SCHEME}"
log_info "Build configuration: ${build_configuration}"
log_info "Sentry organization: ${SENTRY_ORG}"
log_info "Sentry project: ${SENTRY_PROJECT}"

mkdir -p "${TEMP_DIR}"

# -----------------------------------------------------------------------------
log_stage "Creating app bundle"

readonly staging_dir="${TEMP_DIR}/Staging"
readonly export_options_plist_path="${TEMP_DIR}/ExportOptions.plist"
readonly archive_path="${TEMP_DIR}/${product_name} ${version_and_build_number}.xcarchive"
readonly bundle_path="${staging_dir}/${product_name}.app"

run_command "Archiving application" xcodebuild archive \
  -project "${XCODE_PROJECT_PATH}" \
  -scheme "${BUILD_SCHEME}" \
  -configuration "${build_configuration}" \
  -archivePath "${archive_path}"

log_info "Creating \"ExportOptions.plist\""
command cat > "${export_options_plist_path}" <<- EOF
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>signingStyle</key>
	<string>automatic</string>
	</dict>
	</plist>
EOF

mkdir -p "${staging_dir}"

run_command "Exporting app bundle" xcodebuild \
  -exportArchive \
  -archivePath "${archive_path}" \
  -exportPath "${staging_dir}" \
  -exportOptionsPlist "${export_options_plist_path}"

# -----------------------------------------------------------------------------
log_stage "Notarizing app bundle"

readonly unnotarized_bundle_zip_path="${TEMP_DIR}/${product_name} ${version_and_build_number} Unnotarized.zip"

run_command "Zipping app bundle for notarization" ditto -c -k --sequesterRsrc --keepParent "${bundle_path}" "${unnotarized_bundle_zip_path}"

run_command "Submitting zip file to notary service" xcrun notarytool submit \
  --wait \
  --team-id "${DEVELOPMENT_TEAM}" \
  --apple-id "${apple_id}" \
  --password "${notarytool_password}" \
  "${unnotarized_bundle_zip_path}"

run_command "Stapling notarization ticket to app bundle" xcrun stapler staple "${bundle_path}"

rm -f "${unnotarized_bundle_zip_path}" 2>/dev/null

# -----------------------------------------------------------------------------
log_stage "Creating release artefacts"

readonly notarized_bundle_zip_path="${TEMP_DIR}/${product_name} ${version_and_build_number}.zip"

if [[ "${release_configuration_key}" == "${PRODUCTION_RELEASE_CONFIGURATION_KEY}" ]]; then
  readonly dmg_path="${TEMP_DIR}/${DMG_FILENAME}"

  run_command "Creating DMG" create-dmg \
    --volname "${product_name}" \
    --background "${DMG_BACKGROUND_PATH}" \
    --window-pos "${DMG_WINDOW_POS_X}" "${DMG_WINDOW_POS_Y}" \
    --window-size "${DMG_WINDOW_WIDTH}" "${DMG_WINDOW_HEIGHT}" \
    --icon-size "${DMG_ICON_SIZE}" \
    --icon "${bundle_path:t}" "${DMG_APP_ICON_POS_X}" "${DMG_APP_ICON_POS_Y}" \
    --hide-extension "${bundle_path:t}" \
    --app-drop-link "${DMG_APP_DROP_LINK_POS_X}" "${DMG_APP_DROP_LINK_POS_Y}" \
    "${dmg_path}" \
    "${staging_dir}"

  run_command "Signing DMG with Developer ID" codesign --sign "${SIGNING_IDENTITY}" "${dmg_path}"
  run_command "Zipping app archive" ditto -c -k --sequesterRsrc --keepParent "${archive_path}" "${RELEASES_DIR}/${archive_path:t}.zip"
fi

run_command "Zipping notarized app bundle" ditto -c -k --sequesterRsrc --keepParent "${bundle_path}" "${notarized_bundle_zip_path}"

# -----------------------------------------------------------------------------
log_stage "Uploading debug symbols to Sentry"

run_command "Uploading dSYMs" sentry-cli debug-files upload \
  --include-sources \
  --auth-token "${sentry_auth_token}" \
  --org "${SENTRY_ORG}" \
  --project "${SENTRY_PROJECT}" \
  ${archive_path}/dSYMs

# -----------------------------------------------------------------------------
log_stage "Creating GitHub release"

typeset current_dir="${PWD}"

cd "${release_repository_dir}"

if git rev-parse -q --verify "refs/tags/v${version}" &>/dev/null; then
  log_warning "Tag 'v${version}' already exists, skipping creation"
else
  run_command "Creating tag" git tag -a "v${version}" -m "Release version ${version_and_build_number}"
  run_command "Pushing tag to remote repository" git push origin "v${version}"
fi

typeset release_artefacts_dir="${RELEASES_DIR}/To upload"
typeset release_artefacts_uploaded=0
typeset release_is_draft=0

if gh release view "v${version}" &>/dev/null; then
  log_warning "Release for tag 'v${version}' already exists, skipping creation"

  mkdir -p "${release_artefacts_dir}"

  if [[ "${release_configuration_key}" == "${PRODUCTION_RELEASE_CONFIGURATION_KEY}" ]]; then
    cp "${dmg_path}" "${release_artefacts_dir}/${dmg_path:t}"
  fi

  cp "${notarized_bundle_zip_path}" "${release_artefacts_dir}/${notarized_bundle_zip_path:t}"
else
  typeset draft_flag=""
  typeset -a artefacts_to_upload=("${notarized_bundle_zip_path}")

  if [[ "${release_configuration_key}" == "${PRODUCTION_RELEASE_CONFIGURATION_KEY}" ]]; then
    release_is_draft=1
    draft_flag="--draft"
    artefacts_to_upload+=("${dmg_path}")
  fi

  run_command "Creating release and uploading artefacts" gh release create "v${version}" \
    --title "Release ${version}" \
    --latest \
    "${draft_flag}" \
    "${artefacts_to_upload[@]}"

  release_artefacts_uploaded=1
fi

cd "${current_dir}"

# -----------------------------------------------------------------------------
log_stage "Release process complete"

rm -rf "${TEMP_DIR}" 2>/dev/null

if (( release_artefacts_uploaded )); then
  typeset github_release_url_label="GitHub release"

  if (( release_is_draft )); then
    github_release_url_label+=" (draft)"
  fi

  log_info "${github_release_url_label}: http://github.com/${RELEASE_REPOSITORY_OWNER}/${release_repository_name}/releases/tag/v${version}"
else
  log_warning "Release artefacts ready for manual upload in: ${release_artefacts_dir}"
fi
