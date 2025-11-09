#!/bin/zsh

if [[ -z "$1" ]]; then
  print -u2 "Usage: ${0:t} <command_name>"
  exit 1
fi

top -stats command,cpu,mem | grep "${1::15}"
