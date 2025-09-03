#!/bin/zsh

readonly LOG_DIR="${0:A:h}/../.logs"
readonly LOG_PATH="${LOG_DIR}/debug.log"
readonly BOLD=$'\033[1m'
readonly RESET=$'\033[0m'

mkdir -p "${LOG_DIR}"
print "Log formatter started...\n"
tail -F "${LOG_PATH}" | awk -v bold="${BOLD}" -v reset="${RESET}" '
/^[0-9]{4}-[0-9]{2}-[0-9]{2}/ {
  original_line               = $0
  date_part               = $1 # YYYY-MM-DD
  time_fraction_timezone  = $2 # HH:MM:SS.microseconds+TZ
  process_token           = $3 # ProcessName[pid:thread]

  split(time_fraction_timezone, time_parts, ".")
  time_hms = time_parts[1]
  end_of_process_token_pos = index(original_line, "] ")

  if (end_of_process_token_pos == 0) next

  remaining_text = substr(original_line, end_of_process_token_pos + 2) # Pattern: [Category] rest-of-message

  category = ""
  message  = remaining_text

  if (substr(remaining_text, 1, 1) == "[") {
    closing_bracket_pos = index(remaining_text, "]")

    if (closing_bracket_pos > 0) {
      category = substr(remaining_text, 2, closing_bracket_pos - 2)
      message  = substr(remaining_text, closing_bracket_pos + 1)
      sub(/^[ \t]+/, "", message)
    }
  }

  printf("%s %s‣ %s%s\n%s\n\n", time_hms, bold, category, reset, message)
  next
}
{
  print
}
'