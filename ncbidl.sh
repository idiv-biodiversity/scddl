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
# shellcheck source=util.sh
source "$(dirname "$0")"/util.sh

# -----------------------------------------------------------------------------
# usage
# -----------------------------------------------------------------------------

function usage { cat << EOF
$app $version

USAGE

  $app [options] [--] dataset output

DESCRIPTION

  download NCBI data set

ARGUMENTS

  dataset               the remote data set to download from the ftp server,
                        example: blast/db/nr

  output                the local data set directory,
                        example: /data/db

                        the data set will be put in:
                        \$output/ncbi/\$dataset/\$(date +%F)

  --                    ends option parsing

OPTIONS

  -p, --parallel cores  use \$cores parallel downloads,
                        default: number of cores available

  -v, --verbose         output every command as it executes
  -q, --quiet           disables verbose

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

    -q|--quiet)
      verbose=no
      shift
      ;;

    -v|--verbose)
      verbose=yes
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
dataset=$1
shift || bailout "missing argument: data set"
output_prefix=$1
shift || bailout "missing argument: output"
set -o nounset

if [[ "$*" != "" ]]
then
  bailout "trailing arguments: $*"
fi

# trim trailing slashes
shopt -s extglob
dataset="${dataset%%+(/)}"
output_prefix="${output_prefix%%+(/)}"
shopt -u extglob

# -----------------------------------------------------------------------------
# verbose: output configuration
# -----------------------------------------------------------------------------

[[ $verbose == yes ]] &&
cat << EOF
dataset: $dataset
output: $output_prefix

parallel: $cores CPU cores

versions:
- $app $version
- $(lftp --version | head -1)

EOF

# -----------------------------------------------------------------------------
# check arguments
# -----------------------------------------------------------------------------

[[ -n $dataset ]] ||
  bailout "no remote data set specified"

[[ -n $output_prefix ]] ||
  bailout "local data set directory not specified"

[[ -d $output_prefix ]] ||
  bailout "local data set directory does not exist: $output_prefix"

# -----------------------------------------------------------------------------
# preparation
# -----------------------------------------------------------------------------

tmpdir=$(mktemp -d --tmpdir="$output_prefix" ".$app-XXXXXXXXXX")
trap 'rm -fr "$tmpdir"' EXIT INT TERM

download_date=$(date +%F)

output_basedir="$output_prefix/ncbi/$dataset"

output_dir="$output_basedir/$download_date"

# -----------------------------------------------------------------------------
# application functions
# -----------------------------------------------------------------------------

function download {
  local v
  [[ $verbose == yes ]] &&
    v=y

  cat << EOF | lftp ftp://ftp.ncbi.nlm.nih.gov
# bigger socket buffer, better I/O
set net:socket-buffer 33554432

# use IPv4 only
set dns:order "inet"

# download md5s first
mirror ${v:+-v} -r -p -P $cores -i \
       "^$(basename "$dataset").*\\.gz\\.md5$" \
       /$(dirname "$dataset") $tmpdir

# then download tarballs
mirror ${v:+-v} -r -p -P $cores -i \
       "^$(basename "$dataset").*\\.gz$" \
       /$(dirname "$dataset") $tmpdir
EOF
}

# -----------------------------------------------------------------------------
# application
# -----------------------------------------------------------------------------

[[ $verbose == yes ]] &&
  log.info "starting download of $dataset"

download ||
  bailout 'download failed'

[[ $verbose == yes ]] &&
  log.info "checking md5 checksums"

pushd "$tmpdir" &> /dev/null

find . -name '*.md5' |
  while read -r hash
  do
    cat "$hash"
    rm "$hash"
  done |
  md5sum -c --quiet ||
  bailout 'verification error'

[[ $verbose == yes ]] &&
  log.info "extracting files"

find . -type f |
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
        bailout "do not recognize file type, open issue https://github.com/idiv-biodiversity/scddl/issues"
        ;;
    esac
  done

popd &> /dev/null

[[ $verbose == yes ]] &&
  log.info "moving from tmp dir to final destination"

mkdir -p "$(dirname "$output_dir")"

mv -n "$tmpdir" "$output_dir" ||
  bailout "moving failed"

[[ $verbose == yes ]] &&
  log.info "setting read only"

chmod -R -w "$output_dir"

log.info "done"
