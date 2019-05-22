#!/usr/bin/env bash

# safety first
set \
  -o errexit \
  -o pipefail \
  -o noglob \
  -o nounset \

app=$(basename "$0" .sh)

version=$(git describe --always --long --dirty 2> /dev/null) ||
  version="0.3.0"

# get utilities
# shellcheck source=util.sh
source "$(dirname "$0")"/util.sh

# -----------------------------------------------------------------------------
# usage
# -----------------------------------------------------------------------------

function usage { cat << EOF
$app $version

USAGE

  $app [options] [--] prefix dataset...

DESCRIPTION

  download UCSC data set

ARGUMENTS

  prefix                the local data set directory,
                        example: /data/db

                        the data sets will be put in:
                        \$prefix/ucsc/\$dataset/\$(date +%F)

  dataset...            the remote data sets to download from the ftp server,
                        example: goldenPath/xenTro9/bigZips/refMrna.fa

  --                    ends option parsing

OPTIONS

  -p, --parallel cores  use \$cores parallel downloads,
                        default: number of cores available

OUTPUT OPTIONS

      --color[=WHEN]    whether to use colored output
                        WHEN can be 'always', 'yes', 'never', 'no', or 'auto'

      --syslog          write output to syslog, useful for cron jobs
                        note: systemd timers usually do not need this because
                        output is automatically sent to the journal

      --debug           output every command as it executes
  -v, --verbose         enables verbose output
  -q, --quiet           disables both debug and verbose

OTHER OPTIONS

  -?, --help            shows this help text
  --version             shows this tools version

EOF
}

# -----------------------------------------------------------------------------
# external tools
# -----------------------------------------------------------------------------

tool.available lftp

# -----------------------------------------------------------------------------
# configuration
# -----------------------------------------------------------------------------

cores=$(grep -c ^processor /proc/cpuinfo)
color=auto
syslog=no
debug=no
verbose=no

ignore_next_arg=no

for arg in "$@"
do
  if [[ $ignore_next_arg == yes ]]
  then
    ignore_next_arg=no
    continue
  fi

  case "$arg" in
    -\?|--help)
      usage
      exit
      ;;

    --version)
      echo "$app $version"
      exit
      ;;

    -p|--parallel)
      shift
      cores=${1:?"parallel option has no argument"}
      [[ $cores =~ ^[0-9]+$ ]] ||
        bailout "parallel option argument is not a number: $cores"
      ignore_next_arg=yes
      shift
      ;;

    --color|--color=always|--color=yes)
      color=yes
      shift
      ;;

    --color=never|--color=no)
      color=no
      shift
      ;;

    --color=auto)
      color=auto
      shift
      ;;

    --syslog)
      syslog=yes
      shift
      ;;

    --debug)
      debug=yes
      shift
      ;;

    --debug=yes|--debug=no)
      debug=${arg##--debug=}
      shift
      ;;

    -q|--quiet)
      debug=no
      verbose=no
      shift
      ;;

    -v|--verbose)
      verbose=yes
      shift
      ;;

    --verbose=yes|--verbose=no)
      verbose=${arg##--verbose=}
      shift
      ;;

    --)
      shift
      break
      ;;

    -*)
      bailout "unrecognized option: $arg"
      ;;

    *)
      break
      ;;
  esac
done

set +o nounset
prefix=$1
shift || bailout "missing argument: prefix"
set -o nounset

shopt -s extglob
# trim trailing slashes
prefix="${prefix%%+(/)}"

datasets=()
for d in "$@"
do
  datasets+=("${d%%+(/)}")
done

shopt -u extglob

[[ ${#datasets[@]} -gt 0 ]] ||
  bailout 'missing argument: dataset'

# -----------------------------------------------------------------------------
# verbose: output configuration
# -----------------------------------------------------------------------------

if [[ $verbose == yes ]]
then
  cat << EOF
prefix: $prefix
datasets:
EOF
  for d in "${datasets[@]}"
  do
    echo "- $d"
  done
  cat << EOF
parallel: $cores CPU cores

versions:
- $app $version
- $(lftp --version | head -1)

EOF

  md5sum_verbosity=""
else
  md5sum_verbosity="--quiet"
fi

# -----------------------------------------------------------------------------
# debug mode
# -----------------------------------------------------------------------------

[[ $debug == yes ]] &&
  set -o xtrace

# -----------------------------------------------------------------------------
# check arguments
# -----------------------------------------------------------------------------

[[ -d $prefix ]] ||
  bailout "local data set directory does not exist: $prefix"

download_date=$(date +%F)

# -----------------------------------------------------------------------------
# preparation
# -----------------------------------------------------------------------------

tmpdir=$(mktemp -d --tmpdir="$prefix" ".$app-XXXXXXXXXX")
trap 'rm -fr "$tmpdir"' EXIT INT TERM

# -----------------------------------------------------------------------------
# application functions
# -----------------------------------------------------------------------------

function download {
  local v
  [[ $verbose == yes ]] &&
    v=y

  cat << EOF | lftp ftp://hgdownload.cse.ucsc.edu
# bigger socket buffer, better I/O
set net:socket-buffer 33554432

# use IPv4 only
set dns:order "inet"

# download md5s first
mirror ${v:+-v} -r -p -P $cores -i \
       "^md5sum.txt$" \
       /$(dirname "$dataset") $tmpdir

mirror ${v:+-v} -r -p -P $cores -i \
       "^$(basename "$dataset").*md5$" \
       /$(dirname "$dataset") $tmpdir

# then download tarballs (excluding everything not ending with md5)
mirror ${v:+-v} -r -p -P $cores -i \
       "^$(basename "$dataset").*" \
       /$(dirname "$dataset") $tmpdir \
       -x .md5$
EOF
}

# -----------------------------------------------------------------------------
# application
# -----------------------------------------------------------------------------

for dataset in "${datasets[@]}"
do
  output_basedir="$prefix/ucsc/$dataset"

  output_dir="$output_basedir/$download_date"

  if [[ -e $output_dir ]]
  then
    log.info "skipping $dataset: already exists"
    continue
  fi

  log.verbose "starting download of $dataset"

  download ||
    bailout 'download failed'

  log.verbose 'verifying download'

  pushd "$tmpdir" &> /dev/null

  # for verification, we have two possible cases ...
  {
    # ... a) standard md5 file
    if [[ -f md5sum.txt ]]
    then
      find . -type f ! -name md5sum.txt -and ! -name '*.md5' |
        while read -r file
        do
          file=$(basename "$file")
          awk \
            -v file="$file" \
            '$2 == file' \
            md5sum.txt
        done

      rm -f md5sum.txt
    fi

    # ... b) an md5 file per data file
    while read -r file
    do
      cat "$file"
      rm -f "$file"
    done < <(find . -type f -name '*.md5')
  } |
    md5sum -c $md5sum_verbosity ||
    bailout 'verification error'

  log.verbose "extracting files"

  while read -r file
  do
    extract "$file"
  done < <(find . -type f)

  popd &> /dev/null

  log.verbose "moving from tmp dir to final destination"

  mkdir -p "$(dirname "$output_dir")"

  mv -n "$tmpdir" "$output_dir" ||
    bailout "moving failed"

  chmod -R +r "$output_dir"
done

log.verbose "done"
