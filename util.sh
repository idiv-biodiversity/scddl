#!/usr/bin/env bash

declare app

function log.info {
  if [[ -t 0 ]]
  then
    echo -e "\\e[1m$app: $*\\e[0m"
  else
    logger -p user.info -t "$app" "$@"
  fi
}

function log.error {
  if [[ -t 0 ]]
  then
    echo -e "\\e[1m\\e[31m$app: $*\\e[0m" >&2
  else
    logger -p user.err -t "$app" "$@"
  fi
}

# $1 message
# $2 exit status, optional, defaults to 1
function bailout {
  log.error "$1"
  exit "${2:-1}"
}

function tool.available {
  local tool=$1

  if ! command -v "$tool" &> /dev/null
  then
    bailout "$tool not found"
  fi
}
