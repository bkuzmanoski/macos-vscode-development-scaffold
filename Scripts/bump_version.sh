#!/bin/zsh

if (($# < 2)); then
  print -u2 "Usage: ${0:t} [--major|--minor|--patch] <xcode_project_path>"
  exit 1
fi

readonly VERSION_BUMP_TYPE="$1"
readonly XCODE_PROJECT_PATH="$2"
readonly XCODE_PROJECT_SETTINGS_PATH="${XCODE_PROJECT_PATH}/project.xcproj"

readonly MARKETING_VERSION_KEY_PATTERN='"MARKETING_VERSION(\[[^]]*\])?"[[:space:]]*:[[:space:]]*'
readonly CURRENT_PROJECT_VERSION_KEY_PATTERN='"CURRENT_PROJECT_VERSION(\[[^]]*\])?"[[:space:]]*:[[:space:]]*'
readonly VALUE_PATTERN='"([^"]*)"'

if [[ ! -f "${XCODE_PROJECT_SETTINGS_PATH}" ]]; then
  print -u2 "Error: Could not find Xcode project settings: ${XCODE_PROJECT_SETTINGS_PATH}"
  exit 1
fi

typeset -a project_settings_lines=("${(@f)$(<"${XCODE_PROJECT_SETTINGS_PATH}")}")
typeset current_marketing_version
typeset current_project_version

for line in "${project_settings_lines[@]}"; do
  if [[ -z "${current_marketing_version}" && "${line}" =~ ${MARKETING_VERSION_KEY_PATTERN}${VALUE_PATTERN} ]]; then
    current_marketing_version=${match[2]:=}
  elif [[ -z "${current_project_version}" && "${line}" =~ ${CURRENT_PROJECT_VERSION_KEY_PATTERN}${VALUE_PATTERN} ]]; then
    current_project_version=${match[2]:=}
  fi

  if [[ -n "${current_marketing_version}" && -n "${current_project_version}" ]]; then
    break
  fi
done

if [[ -z "${current_marketing_version}" || -z "${current_project_version}" ]]; then
  print -u2 "Error: Could not find current version or build number."
  exit 1
fi

typeset -a marketing_version_parts=("${(@s:.:)current_marketing_version}")

if [[ "${#marketing_version_parts[@]}" -ne 3 ]]; then
  print -u2 "Error: Current version '${current_marketing_version}' is not in 'MAJOR.MINOR.PATCH' format."
  exit 1
fi

case "${VERSION_BUMP_TYPE}" in
--major)
  ((marketing_version_parts[1]++))
  marketing_version_parts[2]=0
  marketing_version_parts[3]=0
  ;;
--minor)
  ((marketing_version_parts[2]++))
  marketing_version_parts[3]=0
  ;;
--patch)
  ((marketing_version_parts[3]++))
  ;;
esac

typeset new_marketing_version="${(j:.:)marketing_version_parts}"
typeset new_project_version=$((current_project_version + 1))

sed -i '' -E "s/(${MARKETING_VERSION_KEY_PATTERN})${VALUE_PATTERN}/\\1\"${new_marketing_version}\"/g" "${XCODE_PROJECT_SETTINGS_PATH}"
sed -i '' -E "s/(${CURRENT_PROJECT_VERSION_KEY_PATTERN})${VALUE_PATTERN}/\\1\"${new_project_version}\"/g" "${XCODE_PROJECT_SETTINGS_PATH}"

print "Marketing Version:              ${current_marketing_version}\t→ ${new_marketing_version}"
print "Project Version (Build Number): ${current_project_version}\t→ ${new_project_version}"
