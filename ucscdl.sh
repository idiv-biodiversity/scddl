#!/usr/bin/env bash

# safety first
set \
  -o errexit \
  -o pipefail \
  -o noglob \
  -o nounset \

app=$(basename "$0" .sh)

version=$(git describe --always --long --dirty 2> /dev/null) ||
  version="0.1.0"

# get utilities
# shellcheck disable=SC1091
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
                        example: blast/db/nr

  --                    ends option parsing

OPTIONS

  -p, --parallel cores  use \$cores parallel downloads,
                        default: number of cores available

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
debug=no
verbose=no

for arg in "$@"
do
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
      shift
      ;;

    --debug)
      debug=yes
      shift
      ;;

    --debug=yes|--debug=no)
      debug=${1##--debug=}
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
      verbose=${1##--verbose=}
      shift
      ;;

    --)
      shift
      break
      ;;

    -*)
      bailout "unrecognized option: $1"
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

  # if there is a md5sum.txt then extract the md5s for the downloaded files 
  # and save them in separate md5 files (one per download). this is done 
  # because ucsc has a mixture of md5 per file and a md5sum.txt file .. 
  # also in the same directory
  if [[ -f md5sum.txt ]]; then
    while read -r line
    do
      fname=$(echo "$line" | sed 's/  / /; s/*//'| cut -d" " -f 2)
      if [[ -f "$fname" ]]; then
        echo "$line" > "$fname.md5"
      fi
    done < md5sum.txt
    rm md5sum.txt 
  fi

  # now check the available md5s
  find . -name '*.md5' |
    while read -r hash
    do
      cat "$hash"
      rm "$hash"
    done |
    md5sum -c $md5sum_verbosity ||
    bailout 'verification error'

  log.verbose "extracting files"

  while read -r file
  do
    case "$file" in
      *.tar.gz)
        tar xzfo "$file" ||
          bailout "extracting $file failed"
        rm -f "$file"
        ;;

      *.gz)
        gunzip "$file" ||
          bailout "decompressing $file failed"
        ;;

      *)
        # ucsc also has uncompressed files \
        ;;
    esac
  done < <(find . -type f)

  popd &> /dev/null

  log.verbose "moving from tmp dir to final destination"

  mkdir -p "$(dirname "$output_dir")"

  mv -n "$tmpdir" "$output_dir" ||
    bailout "moving failed"

  chmod -R +r "$output_dir"
done

log.verbose "done"
