#!/bin/zsh

if (($# < 2)); then
  print -u2 "Usage: ${0:t} [--major|--minor|--patch] <version_xcconfig_path>"
  exit 1
fi

readonly VERSION_BUMP_TYPE="$1"
readonly VERSION_XCCONFIG_PATH="$2"

readonly MARKETING_VERSION_PATTERN='^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]*)[[:space:]]*$'
readonly CURRENT_PROJECT_VERSION_PATTERN='^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]*)[[:space:]]*$'

if [[ ! -f "${VERSION_XCCONFIG_PATH}" ]]; then
  print -u2 "Error: Could not find ${VERSION_XCCONFIG_PATH}"
  exit 1
fi

typeset -a xcconfig_lines=("${(@f)$(<"${VERSION_XCCONFIG_PATH}")}")
typeset current_marketing_version
typeset current_project_version

for line in "${xcconfig_lines[@]}"; do
  if [[ "${line}" =~ ${MARKETING_VERSION_PATTERN} ]]; then
    current_marketing_version=${match[1]}
  elif [[ "${line}" =~ ${CURRENT_PROJECT_VERSION_PATTERN} ]]; then
    current_project_version=${match[1]}
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

if [[ ! "${current_project_version}" =~ ^[0-9]+$ ]]; then
  print -u2 "Error: Current build number '${current_project_version}' is not an integer."
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
*)
  print -u2 "Error: Invalid version bump type '${VERSION_BUMP_TYPE}'."
  exit 1
  ;;
esac

typeset new_marketing_version="${(j:.:)marketing_version_parts}"
typeset new_project_version=$((current_project_version + 1))

for ((i = 1; i <= ${#xcconfig_lines[@]}; i++)); do
  if [[ "${xcconfig_lines[i]}" =~ ${MARKETING_VERSION_PATTERN} ]]; then
    xcconfig_lines[i]="MARKETING_VERSION = ${new_marketing_version}"
  elif [[ "${xcconfig_lines[i]}" =~ ${CURRENT_PROJECT_VERSION_PATTERN} ]]; then
    xcconfig_lines[i]="CURRENT_PROJECT_VERSION = ${new_project_version}"
  fi
done

print -rl -- "${xcconfig_lines[@]}" >"${VERSION_XCCONFIG_PATH}"

typeset -i current_version_width=$((${#current_marketing_version} > ${#current_project_version} ? ${#current_marketing_version} : ${#current_project_version}))

printf "Marketing Version:              %-*s → %s\n" "${current_version_width}" "${current_marketing_version}" "${new_marketing_version}"
printf "Project Version (Build Number): %-*s → %s\n" "${current_version_width}" "${current_project_version}" "${new_project_version}"
