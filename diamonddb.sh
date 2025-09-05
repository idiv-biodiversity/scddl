#!/usr/bin/env bash

# safety first
set \
  -o errexit \
  -o pipefail \
  -o noglob \
  -o nounset \

app=$(basename "$0" .sh)

version=$(git describe --always --long --dirty 2> /dev/null) ||
  version="0.3.1"

# get utilities
source libscddl.sh

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
                        \$prefix/diamond/\$dataset/\$(date +%F)

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
# configuration
# -----------------------------------------------------------------------------

cores=$(grep -c ^processor /proc/cpuinfo)
color=auto
syslog=no
debug=no
verbose=no

while [[ -v 1 ]]
do
  case "$1" in
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

if [[ $verbose == yes ]]
then
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

  diamond_verbosity="--verbose"
else
  diamond_verbosity="--quiet"
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
# external tools
# -----------------------------------------------------------------------------

tool.available diamond

# -----------------------------------------------------------------------------
# preparation
# -----------------------------------------------------------------------------

download_date=$(date +%F)

name=$(basename "$in")

output_dir="$prefix"/diamond/"$name"/"$download_date"
output="$output_dir/$name.dmnd"
app_log="$output_dir/.scddl.log"

[[ -e $output ]] &&
  bailout 'output already exists, not overwriting'

datasets=()

for dataset in "$in" "$map" "$nodes"
do
  d_path="$prefix/ncbi/$dataset/$download_date"

  if [[ -e "$d_path" ]]
  then
    log.verbose "$dataset already exists, not downloading again"
  else
    log.verbose "adding to download list: $dataset"

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
  log.verbose "downloading datasets"

  bash \
    "$(dirname "$0")"/ncbidl.sh \
    --debug="$debug" \
    --verbose="$verbose" \
    --parallel "$cores" \
    "$prefix" \
    "${datasets[@]}" ||
    bailout 'downloading data sets failed'
else
  log.verbose "all datasets already downloaded"
fi

log.verbose "generating diamond db"

mkdir -p "$output_dir"

_taxonmap="$(find "$d_tm" -name '*.accession2taxid' | head -1)"

run.log \
  "$app_log" \
  diamond \
  makedb \
  $diamond_verbosity \
  --threads "$cores" \
  --in "$d_in"/"$name" \
  --taxonmap "$_taxonmap" \
  --taxonnodes "$d_tn"/nodes.dmp \
  --db "$output" ||
  bailout 'generating diamond db failed'

log.verbose "done"
