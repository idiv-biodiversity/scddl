#!/usr/bin/env bash

declare app
declare verbose

if [[ -t 0 ]]
then
  interactive=yes
fi

if [[ -t 1 ]]
then
  color_out=yes
fi

if [[ -t 2 ]]
then
  color_err=yes
fi

function log.info {
  if [[ $interactive == yes ]]
  then
    if [[ $color_out == yes ]]
    then
      echo -e "\\e[1m$app: $*\\e[0m"
    else
      echo "$app: $*"
    fi
  else
    logger -p user.info -t "$app" "$@"
  fi
}

function log.verbose {
  if [[ $verbose == yes ]]
  then
    log.info "$@"
  fi
}

function log.warning {
  if [[ $interactive == yes ]]
  then
    if [[ $color_err == yes ]]
    then
      echo -e "\\e[1m\\e[31m$app: $*\\e[0m" >&2
    else
      echo "$app: $*" >&2
    fi
  else
    logger -p user.warning -t "$app" "$@"
  fi
}

function log.error {
  if [[ $interactive == yes ]]
  then
    if [[ $color_err == yes ]]
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
