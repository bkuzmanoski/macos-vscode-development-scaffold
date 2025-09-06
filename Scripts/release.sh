#!/bin/zsh

# =============================================================================
# Configuration
# =============================================================================

# Constants
readonly APPNAME="" # TODO: Update
readonly INTERNAL="Internal"
readonly PRODUCTION="Production"
readonly RELEASE_OPTIONS=("${INTERNAL}" "${PRODUCTION}")
readonly OUTPUT_PADDING="           "

# Paths
readonly SCRIPT_DIR="${0:A:h}"
readonly PROJECT_DIR="${SCRIPT_DIR}/.."
readonly RELEASES_DIR="${PROJECT_DIR}/Releases"
readonly ASSETS_DIR="${RELEASES_DIR}/Assets"
readonly TEMP_DIR="${RELEASES_DIR}/Temp"
readonly INTERNAL_ICON_PATH="${ASSETS_DIR}/InternalAppIcon.png" # TODO: Create internal icon
readonly PRODUCTION_ICON_PATH="${PROJECT_DIR}/${APPNAME}/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
readonly PRODUCTION_ICON_BACKUP_PATH="${TEMP_DIR}/AppIcon.png.bak"
readonly COMMAND_OUTPUT_PATH="${TEMP_DIR}/command_output.log"

# 1Password Secrets References
readonly OP_APPLE_ID_REF="op://path/to/secret" # TODO: Update
readonly OP_NOTARYTOOL_PASSWORD_REF="op://path/to/secret" # TODO:  Update
readonly OP_SPARKLE_EDDSA_PRIVATE_KEY_REF="op://path/to/secret" # TODO:  Update
readonly OP_SENTRY_AUTH_TOKEN_REF="op://path/to/secret" # TODO:  Update

# Project Settings
readonly DEVELOPMENT_TEAM="" # TODO: Update
readonly SIGNING_IDENTITY="" # TODO: Update
readonly XCODE_PROJECT_PATH="${PROJECT_DIR}/${APPNAME}.xcodeproj"
readonly BUILD_SCHEME="" # TODO: Update
readonly BUILD_CONFIGURATION="Release"

# Sentry Settings
readonly SENTRY_ORG="" # TODO: Update
readonly SENTRY_PROJECT="" # TODO: Update

# GitHub Settings
readonly RELEASE_REPO_DIR="${PROJECT_DIR}/../release-repo" # TODO: Update
readonly GH_RELEASE_BASE_URL="http://github.com/organization/release-repo/releases/tag" # TODO: Update

# DMG Settings
# TODO: Create background image for DMG and review dimensions/positioning below
readonly DMG_BACKGROUND_PATH="${ASSETS_DIR}/DMGBackground.png"
readonly DMG_WINDOW_POS_X=200
readonly DMG_WINDOW_POS_Y=120
readonly DMG_WINDOW_WIDTH=640
readonly DMG_WINDOW_HEIGHT=540
readonly DMG_ICON_SIZE=100
readonly DMG_APP_ICON_POS_X=167
readonly DMG_APP_ICON_POS_Y=274
readonly DMG_APP_DROP_LINK_POS_X=473
readonly DMG_APP_DROP_LINK_POS_Y=274

# Dependencies
readonly REQUIRED_COMMANDS=("op" "xcodebuild" "jq" "xcrun" "create-dmg" "sentry-cli" "gh")
readonly REQUIRED_XCODE_TOOLS=("agvtool" "notarytool" "stapler")
readonly REQUIRED_PATHS=("${XCODE_PROJECT_PATH}" "${INTERNAL_ICON_PATH}" "${PRODUCTION_ICON_PATH}" "${DMG_BACKGROUND_PATH}")
readonly REQUIRED_SECRETS=( "${OP_APPLE_ID_REF}" "${OP_NOTARYTOOL_PASSWORD_REF}" "${OP_SPARKLE_EDDSA_PRIVATE_KEY_REF}" "${OP_SENTRY_AUTH_TOKEN_REF}")
readonly REQUIRED_BUILD_SETTINGS=("PRODUCT_NAME" "MARKETING_VERSION" "CURRENT_PROJECT_VERSION" "BUILD_DIR" "MACOSX_DEPLOYMENT_TARGET" "SPARKLE_ROOT_URL")

# =============================================================================
# Utility Functions
# =============================================================================

log_stage() { print -P "\n$(date +%H:%M:%S) %B‣ $@%b" }
log_info() { print "${OUTPUT_PADDING}– $@" }
log_success() { print -P "${OUTPUT_PADDING}%F{green}✓ $@%f" }
log_failure() { print -P "${OUTPUT_PADDING}%F{red}✗ $@%f" }
log_warning() { print -P "${OUTPUT_PADDING}%F{yellow}! $@%f" }

log_error() {
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
  print "[$(date +%H:%M:%S)] $@" >> "${COMMAND_OUTPUT_PATH}"
  log_info "${command_description}"

  local output=$("$@" 2>&1)
  local exit_code=$?
  print "${output}\n" >> "${COMMAND_OUTPUT_PATH}"
  if [[ ${exit_code} -ne 0 ]]; then
    clear_lines 1
    log_failure "${command_description}"
    log_error "Last command failed (${exit_code}).\nDetails:${COMMAND_OUTPUT_PATH}"
  fi
}

# =============================================================================
# Release Script
# =============================================================================

log_stage "Select release type"

for ((i=1; i<=${#RELEASE_OPTIONS[@]}; i++)); do
  print "${OUTPUT_PADDING}${i}) ${RELEASE_OPTIONS[$i]}"
done

print ""
lines_to_clear=$(( ${#RELEASE_OPTIONS[@]} + 2 ))
selected_release_type=""
while true; do
  read "REPLY?${OUTPUT_PADDING}Enter choice (1-${#RELEASE_OPTIONS[@]}): "
  if [[ "${REPLY}" =~ ^[1-9][0-9]*$ ]] && (( REPLY >= 1 && REPLY <= ${#RELEASE_OPTIONS[@]} )); then
    selected_release_type="${RELEASE_OPTIONS[$REPLY]}"
    clear_lines ${lines_to_clear}
    log_success "${selected_release_type}"
    break
  else
    clear_lines 1
  fi
done

readonly release_type="${selected_release_type}"

# -----------------------------------------------------------------------------
log_stage "Checking dependencies"

missing_dependencies=0

for command in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "${command}" &>/dev/null; then
    log_failure "${command}"
    missing_dependencies=$((missing_dependencies + 1))
  else
    log_success "${command}"
  fi
done

for xcode_tool in "${REQUIRED_XCODE_TOOLS[@]}"; do
  if ! xcrun --find "${xcode_tool}" &>/dev/null; then
    log_failure "${xcode_tool}"
    missing_dependencies=$((missing_dependencies + 1))
  else
    log_success "${xcode_tool}"
  fi
done

for required_path in "${REQUIRED_PATHS[@]}"; do
  if [ ! -e "${required_path}" ]; then
    log_failure "${required_path}"
    missing_dependencies=$((missing_dependencies + 1))
  else
    log_success "${required_path}"
  fi
done

[[ ${missing_dependencies} -gt 0 ]] && log_error "One or more dependencies are missing."

# -----------------------------------------------------------------------------
log_stage "Retrieving secrets from 1Password"

typeset -A secrets
missing_secrets=()
for secret_ref in "${REQUIRED_SECRETS[@]}"; do
  secret_value=$(op read --no-newline "${secret_ref}" 2>/dev/null)
  if [[ $? -ne 0 || -z "${secret_value}" ]]; then
    log_failure "${secret_ref}"
    missing_secrets+=("${secret_ref}")
  else
    log_success "${secret_ref}"
    secrets[$secret_ref]=${secret_value}
  fi
done
[[ ${#missing_secrets[@]} -gt 0 ]] && log_error "One or more required secrets could not be retrieved."

readonly apple_id=${secrets[${OP_APPLE_ID_REF}]}
readonly notarytool_password=${secrets[${OP_NOTARYTOOL_PASSWORD_REF}]}
readonly sparkle_eddsa_private_key=${secrets[${OP_SPARKLE_EDDSA_PRIVATE_KEY_REF}]}
readonly sentry_auth_token=${secrets[${OP_SENTRY_AUTH_TOKEN_REF}]}

# -----------------------------------------------------------------------------
log_stage "Reading build settings from XCode"

typeset -A build_settings
build_settings_lines=("${(f)"$( \
  xcodebuild -project "${XCODE_PROJECT_PATH}" -scheme "${BUILD_SCHEME}" -showBuildSettings -json 2>/dev/null \
  | jq -r '.[0].buildSettings as $settings | $ARGS.positional[] | ., $settings[.]' --args "${REQUIRED_BUILD_SETTINGS[@]}" 2>/dev/null)"}")
build_settings=("${(@kv)build_settings_lines}")
missing_settings=()
for setting in "${REQUIRED_BUILD_SETTINGS[@]}"; do
  if [[ -z "${build_settings[$setting]}" ]]; then
    log_failure "${setting}"
    missing_settings+=("${setting}")
  else
    log_success "${setting}: ${build_settings[$setting]}"
  fi
done
[[ ${#missing_settings[@]} -gt 0 ]] && log_error "One or more required build settings are missing."

readonly product_name=${build_settings[PRODUCT_NAME]}
readonly version=${build_settings[MARKETING_VERSION]}
readonly build_number=${build_settings[CURRENT_PROJECT_VERSION]}
readonly minimum_system_version=${build_settings[MACOSX_DEPLOYMENT_TARGET]}
readonly build_dir=${build_settings[BUILD_DIR]}
readonly sparkle_root_url=${build_settings[SPARKLE_ROOT_URL]}

# -----------------------------------------------------------------------------
log_stage "Creating working directories"

readonly version_string="${version} (${build_number})"
readonly release_dir="${RELEASES_DIR}/${version_string} (${release_type})"

[[ -d "${release_dir}" ]] && log_error "Release directory already exists: ${release_dir}"
mkdir -p "${release_dir}"
mkdir -p "${TEMP_DIR}"

# -----------------------------------------------------------------------------
log_stage "Starting release process"

log_info "Development team: ${DEVELOPMENT_TEAM}"
log_info "Signing identity: ${SIGNING_IDENTITY}"
log_info "XCode project: ${XCODE_PROJECT_PATH}"
log_info "Build scheme: ${BUILD_SCHEME}"
log_info "Build configuration: ${BUILD_CONFIGURATION}"
log_info "Sentry organization: ${SENTRY_ORG}"
log_info "Sentry project: ${SENTRY_PROJECT}"

# -----------------------------------------------------------------------------
log_stage "Creating app bundle"

readonly staging_dir="${TEMP_DIR}/Staging"
readonly export_options_plist_path="${TEMP_DIR}/ExportOptions.plist"
readonly temp_archive_path="${TEMP_DIR}/${product_name}.xcarchive"

if [[ "${release_type}" == "${INTERNAL}" ]]; then
  run_command "Backing up original app icon" mv "${PRODUCTION_ICON_PATH}" "${PRODUCTION_ICON_BACKUP_PATH}"
  run_command "Replacing app icon with internal version" cp "${INTERNAL_ICON_PATH}" "${PRODUCTION_ICON_PATH}"
fi

run_command "Archiving application" xcodebuild archive \
  -project "${XCODE_PROJECT_PATH}" \
  -scheme "${BUILD_SCHEME}" \
  -configuration "${BUILD_CONFIGURATION}" \
  -archivePath "${temp_archive_path}"

log_info "Creating \"ExportOptions.plist\""
command cat > "${export_options_plist_path}" << EOL
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
EOL

run_command "Creating staging directory" mkdir -p "${staging_dir}"
run_command "Exporting app bundle" xcodebuild -exportArchive \
  -archivePath "${temp_archive_path}" \
  -exportPath "${staging_dir}" \
  -exportOptionsPlist "${export_options_plist_path}"

# -----------------------------------------------------------------------------
log_stage "Notarizing app bundle"

readonly app_filename="${product_name}.app"
readonly app_path="${staging_dir}/${app_filename}"
readonly temp_zip_path="${TEMP_DIR}/${product_name}.zip"

run_command "Zipping app bundle for notarization" ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${temp_zip_path}"
run_command "Submitting zip file to notary service" xcrun notarytool submit --wait \
  --team-id "${DEVELOPMENT_TEAM}" \
  --apple-id "${apple_id}" \
  --password "${notarytool_password}" \
  "${temp_zip_path}"
run_command "Stapling notarization ticket to app bundle" xcrun stapler staple "${app_path}"

# -----------------------------------------------------------------------------
log_stage "Creating release artefacts"

readonly archive_zip_path="${release_dir}/${product_name}.xcarchive.zip"
readonly notarized_bundle_zip_path="${release_dir}/${product_name} ${version_string}.zip"

if [[ "${release_type}" == "${PRODUCTION}" ]]; then
  readonly sparkle_sign_update_bin="${build_dir}/../../${product_name}/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
  readonly dmg_filename="${product_name}.dmg"
  readonly dmg_path="${release_dir}/${dmg_filename}"
  readonly appcast_path="${release_dir}/appcast.xml"

  run_command "Creating DMG" create-dmg \
    --volname "${product_name}" \
    --background "${DMG_BACKGROUND_PATH}" \
    --window-pos "${DMG_WINDOW_POS_X}" "${DMG_WINDOW_POS_Y}" \
    --window-size "${DMG_WINDOW_WIDTH}" "${DMG_WINDOW_HEIGHT}" \
    --icon-size "${DMG_ICON_SIZE}" \
    --icon "${app_filename}" "${DMG_APP_ICON_POS_X}" "${DMG_APP_ICON_POS_Y}" \
    --hide-extension "${app_filename}" \
    --app-drop-link "${DMG_APP_DROP_LINK_POS_X}" "${DMG_APP_DROP_LINK_POS_Y}" \
    "${dmg_path}" \
    "${staging_dir}"
  run_command "Signing DMG with Developer ID" codesign --sign "${SIGNING_IDENTITY}" "${dmg_path}"

  log_info "Generating Sparkle EdDSA Signature"
  command -v "${sparkle_sign_update_bin}" &>/dev/null || log_error "Could not find \`sign_update\` binary at: $(dirname "${sparkle_sign_update_bin}")"
  eddsa_signature_fragment=$(print "${sparkle_eddsa_private_key}" | "${sparkle_sign_update_bin}" --ed-key-file - "${dmg_path}")
  [[ $? -ne 0 || -z "${eddsa_signature_fragment}" ]] && log_error "Failed to generate the Sparkle EdDSA Signature."

  log_info "Generating appcast.xml"
  command cat > "${appcast_path}" << EOL
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
<channel>
  <title>${product_name}</title>
  <item>
    <title>${version}</title>
    <pubDate>$(date -u +"%a, %d %b %Y %H:%M:%S %z")</pubDate>
    <sparkle:version>${build_number}</sparkle:version>
    <sparkle:shortVersionString>${version}</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>${minimum_system_version}</sparkle:minimumSystemVersion>
    <enclosure url="${sparkle_root_url}/${dmg_filename}" ${eddsa_signature_fragment}/>
    <sparkle:criticalUpdate/>
  </item>
</channel>
</rss>
EOL
fi

run_command "Zipping app archive" ditto -c -k --sequesterRsrc --keepParent "${temp_archive_path}" "${archive_zip_path}"
run_command "Zipping notarized app bundle" ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${notarized_bundle_zip_path}"

# -----------------------------------------------------------------------------
log_stage "Uploading debug symbols to Sentry"

run_command "Uploading dSYMs" sentry-cli debug-files upload -include-sources \
  --auth-token "${sentry_auth_token}" \
  --org "${SENTRY_ORG}" \
  --project "${SENTRY_PROJECT}" \
  ${temp_archive_path}/dSYMs

# -----------------------------------------------------------------------------
if [[ "${release_type}" == "${PRODUCTION}" ]]; then
  log_stage "Creating GitHub release"

  readonly tag_name="v${version}"

  cd "${RELEASE_REPO_DIR}"

  if git rev-parse -q --verify "refs/tags/${tag_name}" &>/dev/null; then
    log_warning "Tag ${tag_name} already exists, skipping creation"
  else
    run_command "Creating tag" git tag -a "${tag_name}" -m "Release version ${version_string}"
    run_command "Pushing tag to remote" git push origin "${tag_name}"
  fi

  if gh release view "${tag_name}" &>/dev/null; then
    log_warning "GitHub release ${tag_name} already exists, skipping creation"
  else
    run_command "Creating release and uploading artefacts" gh release create "${tag_name}" --title-string "Release ${version}" --latest --draft "${dmg_path}" "${appcast_path}"
  fi
fi

# -----------------------------------------------------------------------------
log_stage "Finalizing release"

if [[ -f "${PRODUCTION_ICON_BACKUP_PATH}" ]]; then
  run_command "Restoring original app icon" mv "${PRODUCTION_ICON_BACKUP_PATH}" "${PRODUCTION_ICON_PATH}"
fi

cd "${PROJECT_DIR}"
run_command "Incrementing project build number" xcrun agvtool next-version

log_info "Cleaning up temporary files"
rm -rf "${TEMP_DIR}" 2>/dev/null

# -----------------------------------------------------------------------------
log_stage "Release process complete"

log_info "Release artefacts: ${release_dir}"

if [[ "${release_type}" == "${PRODUCTION}" ]]; then
  log_info "GitHub release (draft): ${GH_RELEASE_BASE_URL}"
fi

cd "${release_dir}"
