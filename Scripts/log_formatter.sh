#!/bin/zsh

if (( # < 2 )); then
  print -u2 "Error: Missing arguments."
  print -u2 "Usage: $0 \"<process_path>\" \"<primary_subsystem>\""
  exit 1
fi

readonly PROCESS_PATH="$1"
readonly PRIMARY_SUBSYSTEM="$2"
readonly PREDICATE="processImagePath == \"${PROCESS_PATH}\" AND (subsystem == \"${PRIMARY_SUBSYSTEM}\" OR messageType != 0)"

command log stream --predicate "${PREDICATE}" --style ndjson | {
  read -r header
  jq -r --unbuffered --arg primary_subsystem "${PRIMARY_SUBSYSTEM}" '
    (
      def colors: { "red": "\u001b[31m", "yellow": "\u001b[33m" };
      def bold:   "\u001b[1m";
      def reset:  "\u001b[0m";

      (.timestamp | split(" ")[1] | split(".")[0]) as $time |
      (
        if .messageType == "Fault" then colors.red
        elif .messageType == "Error" then colors.yellow
        elif .messageType == "Warning" then colors.yellow
        else ""
        end
      ) as $color |
      (
        if .subsystem and .subsystem != $primary_subsystem then
          " (\(.subsystem))"
        else
          ""
        end
      ) as $subsystem_str |

      $time + bold + " ‣ " + $color + .category + $subsystem_str + reset + "\n" +
      .eventMessage + "\n"
    )
  '
}
