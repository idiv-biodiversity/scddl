#!/usr/bin/env bash

declare app

function log.info {
  if [[ -t 0 ]]
  then
    if [[ -t 1 ]]
    then
      echo -e "\\e[1m$app: $*\\e[0m"
    else
      echo "$app: $*"
    fi
  else
    logger -p user.info -t "$app" "$@"
  fi
}

function log.error {
  if [[ -t 0 ]]
  then
    if [[ -t 2 ]]
    then
      echo -e "\\e[1m\\e[31m$app: $*\\e[0m" >&2
    else
      echo "$app: $*" >&2
    fi
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
