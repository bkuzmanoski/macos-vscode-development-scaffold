#!/bin/zsh

set -o pipefail

if (($# > 1)) || [[ $# -eq 1 && "$1" != "--check" ]]; then
  print -u2 "Usage: ${0:t} [--check]"
  exit 1
fi

readonly CHECK_ONLY=$((${#} == 1))
readonly SCRIPT_DIR="${0:A:h}"
readonly PROJECT_DIR="${SCRIPT_DIR}/.."

if ! xcrun --find xcprojformatter &>/dev/null; then
  print -u2 "xcprojformatter could not be found (requires Xcode 27.2 or later)."
  exit 1
fi

cd "${PROJECT_DIR}"

typeset -a project_files=(${(f)"$(git ls-files --cached --others --exclude-standard '*.xcproj')"})

if ((${#project_files[@]} == 0)); then
  print -u2 "No project.xcproj files found."
  exit 1
fi

typeset -i invalid_count=0
typeset -i unformatted_count=0
typeset formatted_project

for project_file in "${project_files[@]}"; do
  if ! formatted_project="$(xcrun xcprojformatter "${project_file}" 2>/dev/null)"; then
    print -u2 "${project_file}: $(xcrun xcprojformatter "${project_file}" 2>&1 >/dev/null | head -n 1)"
    invalid_count+=1

  elif ((CHECK_ONLY)); then
    # xcprojformatter silently drops unknown keys, so a diff can also indicate a typo in the project file.
    if ! diff -u "${project_file}" - <<<"${formatted_project}"; then
      unformatted_count+=1
    fi

  else
    print -r -- "${formatted_project}" >"${project_file}"
  fi
done

if ((invalid_count > 0)); then
  print -u2 "\n${invalid_count} project file(s) could not be read."
fi

if ((unformatted_count > 0)); then
  print -u2 "\n${unformatted_count} project file(s) not in canonical form. Review the diff above and run '${0:t}' to fix."
fi

if ((invalid_count + unformatted_count > 0)); then
  exit 1
fi
