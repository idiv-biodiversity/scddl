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

  $app [options] [--] prefix in map nodes

DESCRIPTION

  create diamond database from NCBI data sets

ARGUMENTS

  prefix                the local data set directory,
                        example: /data/db

                        the data set will be put in:
                        \$prefix/diamondncbi/\$dataset/\$(date +%F)

  in                    input reference data set
                        passed to diamond makedb --in
                        example: blast/db/FASTA/pdbaa

  map                   protein accession to taxid mapping data set
                        passed to diamond makedb --taxonmap
                        example:
                          pub/taxonomy/accesion2taxid/pdb.accession2taxid

  nodes                 taxonomy data set
                        passed to diamond makedb --taxonnodes
                        example: pub/taxonomy/taxdump

  --                    ends option parsing

OPTIONS

  -p, --parallel cores  use \$cores parallelism,
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

tool.available diamond

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
prefix=$1
shift || bailout "missing argument: prefix"
in=$1
shift || bailout "missing argument: in"
map=$1
shift || bailout "missing argument: map"
nodes=$1
shift || bailout "missing argument: nodes"
set -o nounset

if [[ "$*" != "" ]]
then
  bailout "trailing arguments: $*"
fi

# trim trailing slashes
shopt -s extglob
prefix="${prefix%%+(/)}"
in="${in%%+(/)}"
map="${map%%+(/)}"
nodes="${nodes%%+(/)}"
shopt -u extglob

# -----------------------------------------------------------------------------
# verbose: output configuration
# -----------------------------------------------------------------------------

[[ $verbose == yes ]] &&
cat << EOF
prefix: $prefix
in: $in
map: $map
nodes: $nodes

parallel: $cores CPU cores

versions:
- $app $version
- $(diamond --version)

EOF

# -----------------------------------------------------------------------------
# check arguments
# -----------------------------------------------------------------------------

[[ -d $prefix ]] ||
  bailout "local data set directory does not exist: $prefix"

# -----------------------------------------------------------------------------
# preparation
# -----------------------------------------------------------------------------

download_date=$(date +%F)

name=$(basename "$in")

output_dir="$prefix"/diamond/"$name"/"$download_date"
mkdir -p "$output_dir"

output="$output_dir/$name.dmnd"

[[ -e $output ]] &&
  bailout 'output already exists, not overwriting'

datasets=()

for dataset in "$in" "$map" "$nodes"
do
  d_path="$prefix/ncbi/$dataset/$download_date"

  if [[ -e "$d_path" ]]
  then
    [[ $verbose == yes ]] &&
      log.info "$dataset already exists, not downloading again"
  else
    [[ $verbose == yes ]] &&
      log.info "adding to download list: $dataset"

    datasets+=("$dataset")
  fi
done

d_in="$prefix/ncbi/$in/$download_date"
d_tm="$prefix/ncbi/$map/$download_date"
d_tn="$prefix/ncbi/$nodes/$download_date"

# -----------------------------------------------------------------------------
# application
# -----------------------------------------------------------------------------

if [[ ${#datasets[@]} -gt 0 ]]
then
  [[ $verbose == yes ]] &&
    log.info "downloading datasets"

  bash \
    "$(dirname "$0")"/ncbidl.sh \
    --parallel "$cores" \
    "$prefix" \
    "${datasets[@]}" ||
    bailout 'downloading data sets failed'
else
  [[ $verbose == yes ]] &&
    log.info "all datasets already downloaded"
fi

[[ $verbose == yes ]] &&
  log.info "generating diamond db"

diamond \
  makedb \
  --threads "$cores" \
  --in "$d_in"/"$name" \
  --taxonmap "$(find "$d_tm" -name '*.accession2taxid' | head -1)" \
  --taxonnodes "$d_tn"/nodes.dmp \
  --db "$output" ||
  bailout 'generating diamond db failed'

if [[ $verbose == yes ]]
then
  log.info "done"
fi
