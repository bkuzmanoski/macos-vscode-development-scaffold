#!/bin/zsh

if (( # < 2 )); then
  print -u2 "Usage: ${0:t} <process_path> <primary_subsystem>"
  exit 1
fi

readonly SCRIPT_DIR="${0:A:h}"
readonly PROCESS_PATH="${1//\"/\\\"}"
readonly PRIMARY_SUBSYSTEM="$2"
readonly PREDICATE="processImagePath == \"${PROCESS_PATH}\" AND (subsystem == \"${PRIMARY_SUBSYSTEM}\" OR messageType == 16 OR messageType == 17)"
readonly IGNORE_FILE_PATH="${SCRIPT_DIR}/.logignore"

function get_ignore_patterns_json() {
  if [[ -f "${IGNORE_FILE_PATH}" ]]; then
    grep --invert-match --extended-regexp '^\s*#|^\s*$' "${IGNORE_FILE_PATH}" | jq --raw-input . | jq --slurp .
  else
    print "[]"
  fi
}

if [[ -f "${IGNORE_FILE_PATH}" ]]; then
    print -u2 "Loaded ignore patterns from: ${IGNORE_FILE_PATH}\n"
fi

set -o pipefail
command log stream --predicate "${PREDICATE}" --level debug --style ndjson | \
  jq --raw-input --unbuffered --raw-output --arg primary_subsystem "${PRIMARY_SUBSYSTEM}" --slurpfile ignore_patterns_json <(get_ignore_patterns_json) '
    try fromjson catch empty |
    ($ignore_patterns_json[0] // []) as $ignored_patterns |
    select(
      (.eventMessage // "") as $message |
      ($ignored_patterns | any( . as $pattern | $message | contains($pattern) ) | not)
    ) |
    (
      def colors: { "Fault": "\u001b[31m", "Error": "\u001b[31m", "Warning": "\u001b[33m" };

      (.timestamp | split(" ")[1] | split(".")[0]) +
      "\u001b[1m" +
      " ‣ " +
      (colors[.messageType] // "") +
      .category +
      (if .subsystem and .subsystem != $primary_subsystem then " (\(.subsystem))" else "" end) +
      "\u001b[0m" +
      "\n" +
      .eventMessage +
      "\n"
    )
  '
