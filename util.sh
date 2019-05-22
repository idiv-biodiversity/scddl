#!/usr/bin/env bash

declare app
declare color
declare syslog
declare verbose

function color.out {
  if [[ $color == yes ]] || [[ $color == auto && -t 1 ]]
  then
    echo yes
  else
    echo no
  fi
}

function color.err {
  if [[ $color == yes ]] || [[ $color == auto && -t 2 ]]
  then
    echo yes
  else
    echo no
  fi
}

function log.info {
  color_out=$(color.out)

  if [[ $syslog == yes ]]
  then
    logger -p user.info -t "$app" "$@"
  elif [[ $color_out == yes ]]
  then
    echo -e "\\e[1m$app: $*\\e[0m"
  else
    echo "$app: $*"
  fi
}

function log.verbose {
  if [[ $verbose == yes ]]
  then
    log.info "$@"
  fi
}

function log.warning {
  color_err=$(color.err)

  if [[ $syslog == yes ]]
  then
    logger -p user.warning -t "$app" "$@"
  elif [[ $color_err == yes ]]
  then
    echo -e "\\e[1m\\e[31m$app: $*\\e[0m" >&2
  else
    echo "$app: $*" >&2
  fi
}

function log.error {
  color_err=$(color.err)

  if [[ $syslog == yes ]]
  then
    logger -p user.err -t "$app" "$@"
  elif [[ $color_err == yes ]]
  then
    echo -e "\\e[1m\\e[31m$app: $*\\e[0m" >&2
  else
    echo "$app: $*" >&2
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

function extract {
  local file=$1

  case "$file" in
    *.tar.gz)
      tar xzfo "$file" ||
        bailout "extraction failed: $file"
      rm -f "$file"
      ;;

    *.gz)
      gunzip "$file" ||
        bailout "decompression failed: $file"
      ;;

    *)
      log.verbose "not extracting unknown format: $file"
      ;;
  esac
}

# run a command and log command line if it was successful
#
# positional arguments:
# - $1 log file name
# - $2 command
# - $x arguments
function run.log {
  local log=$1
  shift

  echo "$*" > "$log"

  "$@" |& tee -a "$log"

  return "${PIPESTATUS[0]}"
}
