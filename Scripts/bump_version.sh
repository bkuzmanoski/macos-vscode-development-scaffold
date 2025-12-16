#!/bin/zsh

if (( # < 2 )); then
  print -u2 "Usage: ${0:t} [--major|--minor|--patch] <xcode_project_path>"
  exit 1
fi

readonly VERSION_BUMP_TYPE="$1"
readonly XCODE_PROJECT_PATH="$2"
readonly XCODE_PROJECT_SETTINGS_PATH="${XCODE_PROJECT_PATH}/project.pbxproj"

if [[ ! -f "${XCODE_PROJECT_SETTINGS_PATH}" ]]; then
  print -u2 "Error: Could not find Xcode project settings: ${XCODE_PROJECT_SETTINGS_PATH}"
  exit 1
fi

typeset -a project_settings_lines=("${(@f)$(<"${XCODE_PROJECT_SETTINGS_PATH}")}")
typeset current_marketing_version
typeset current_project_version

for line in "${project_settings_lines[@]}"; do
  if [[ "${line}" =~ 'MARKETING_VERSION = ([^;]+);' ]]; then
    current_marketing_version=${match[1]}
  elif [[ "${line}" =~ 'CURRENT_PROJECT_VERSION = ([^;]+);' ]]; then
    current_project_version=${match[1]}
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
    (( marketing_version_parts[1]++ ))
    marketing_version_parts[2]=0
    marketing_version_parts[3]=0
    ;;
  --minor)
    (( marketing_version_parts[2]++ ))
    marketing_version_parts[3]=0
    ;;
  --patch)
    (( marketing_version_parts[3]++ ))
    ;;
esac

typeset new_marketing_version="${(j:.:)marketing_version_parts}"
typeset new_project_version=$(( current_project_version + 1 ))

sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${new_marketing_version};/g" "${XCODE_PROJECT_SETTINGS_PATH}"
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = ${new_project_version};/g" "${XCODE_PROJECT_SETTINGS_PATH}"

print "Marketing Version:              ${current_marketing_version}\t→ ${new_marketing_version}"
print "Project Version (Build Number): ${current_project_version}\t→ ${new_project_version}"
