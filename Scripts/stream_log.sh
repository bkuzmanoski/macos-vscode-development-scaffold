#!/bin/zsh

if (( # < 2 )); then
  print -u2 "Usage: ${0:t} <process_path> <primary_subsystem>"
  exit 1
fi

readonly PROCESS_PATH="$1"
readonly PRIMARY_SUBSYSTEM="$2"
readonly PREDICATE="processImagePath == \"${PROCESS_PATH}\" AND (subsystem == \"${PRIMARY_SUBSYSTEM}\" OR messageType != 0)"

command log stream --predicate "${PREDICATE}" --style ndjson | {
  read -r header
  jq -r --unbuffered --arg primary_subsystem "${PRIMARY_SUBSYSTEM}" '
    def colors: {
      "Fault": "\u001b[31m",
      "Error": "\u001b[31m",
      "Warning": "\u001b[33m"
    };

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
  '
}
