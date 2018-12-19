#!/usr/bin/env bash

# safety first
set \
  -o errexit \
  -o pipefail \
  -o noglob \
  -o nounset \

app=$(basename "$0" .sh)

version=$(git describe --always --long --dirty 2> /dev/null) ||
  version="0.2.0"

# get utilities
# shellcheck source=../util.sh
source "$(dirname "$0")"/../util.sh

# -----------------------------------------------------------------------------
# usage
# -----------------------------------------------------------------------------

function usage { cat << EOF
$app $version

USAGE

  $app [options] [--] prefix input

DESCRIPTION

  create MALT database from NCBI data sets

ARGUMENTS

  prefix                the local data set directory,
                        example: /data/db

                        the data set will be put in:
                        \$prefix/malt/\$dataset/\$(date +%F)

  input                 input reference data set
                        passed to malt-build --input
                        example: blast/db/FASTA/nt

  --                    ends option parsing

OPTIONS

  -p, --parallel cores  use \$cores parallelism,
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

tool.available malt-build
tool.available unzip

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
input=$1
shift || bailout "missing argument: input"
set -o nounset

if [[ "$*" != "" ]]
then
  bailout "trailing arguments: $*"
fi

# trim trailing slashes
shopt -s extglob
prefix="${prefix%%+(/)}"
input="${input%%+(/)}"
shopt -u extglob

# -----------------------------------------------------------------------------
# verbose: output configuration
# -----------------------------------------------------------------------------

if [[ $verbose == yes ]]
then
  cat << EOF
prefix: $prefix
input: $input

parallel: $cores CPU cores

versions:
- $app $version
- malt-build $(malt-build --help |& grep -oE 'version [[:digit:]\.]+')

EOF

  malt_verbosity="--verbose"
else
  malt_verbosity=""
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

# -----------------------------------------------------------------------------
# preparation
# -----------------------------------------------------------------------------

download_date=$(date +%F)

name=$(basename "$input")

output="$prefix"/malt/"$name"/"$download_date"
app_log="$output/.scddl.log"

[[ -e $output ]] &&
  bailout 'output already exists, not overwriting'

input_path="$prefix/ncbi/$input/$download_date"

acc2tax_url="http://ab.inf.uni-tuebingen.de/data/software/megan6/download/nucl_acc2tax-Nov2018.abin.zip"
acc2tax_dl="$prefix/megan/nucl_acc2tax-Nov2018.abin.zip"
acc2tax="$prefix/megan/nucl_acc2tax-Nov2018.abin"
acc2tax_name=$(basename "$acc2tax")

# -----------------------------------------------------------------------------
# application
# -----------------------------------------------------------------------------

if [[ -e "$input_path" ]]
then
  log.verbose "$input already exists, not downloading again"
else
  log.verbose "downloading $input"

  bash \
    "$(dirname "$0")"/ncbidl.sh \
    --debug="$debug" \
    --verbose="$verbose" \
    --parallel "$cores" \
    "$prefix" \
    "$input" ||
    bailout "downloading $input failed"
fi

if [[ -e "$acc2tax" ]]
then
  log.verbose "$acc2tax_name already exists, not downloading again"
else
  log.verbose "downloading $acc2tax_name)"

  if [[ $verbose == yes ]]
  then
    wget_verbose=""
  else
    wget_verbose="--quiet"
  fi

  mkdir -p "$(dirname "$acc2tax_dl")"

  wget $wget_verbose -O "$acc2tax_dl" "$acc2tax_url" ||
    bailout "downloading $acc2tax_name failed"

  pushd "$(dirname "$acc2tax_dl")" &> /dev/null

  unzip "$acc2tax_dl" ||
    bailout "extracting $acc2tax_name failed"

  rm -f "$acc2tax_dl"

  popd &> /dev/null
fi

log.verbose "generating malt index"

mkdir -p "$output"

run.log \
  "$app_log" \
  malt-build \
  $malt_verbosity \
  --threads "$cores" \
  --input "$input_path"/"$name" \
  --sequenceType DNA \
  --acc2taxonomy "$acc2tax" \
  --index "$output" ||
  bailout 'generating malt index failed'

log.verbose "done"
