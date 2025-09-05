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

  $app [options] [--] prefix dataset...

DESCRIPTION

  download ENSEMBL data set

ARGUMENTS

  prefix                the local data set directory,
                        example: /data/db

                        the data sets will be put in:
                        \$prefix/ensembl/\$dataset/\$(date +%F)

  dataset...            the remote data sets to download from the ftp server,
                        example: pub/release-93/fasta/gallus_gallus/dna/Gallus_gallus

  --                    ends option parsing

OPTIONS

  -g, --ensemblgenome   download from ensemblgenome instead of ensembl
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
# configuration
# -----------------------------------------------------------------------------

cores=$(grep -c ^processor /proc/cpuinfo)
color=auto
syslog=no
debug=no
verbose=no
ensembl_server="ensembl"

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

    -g|--ensemblgenome)
      ensembl_server="ensemblgenomes"
      shift
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
# external tools
# -----------------------------------------------------------------------------

tool.available lftp

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

  cat << EOF | lftp ftp://ftp.$ensembl_server.org
# bigger socket buffer, better I/O
set net:socket-buffer 33554432

# use IPv4 only
set dns:order "inet"

# download md5s first
mirror ${v:+-v} -r -p -P $cores -i \
       "^(CHECKSUMS|MD5SUM)$" \
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

for dataset in "${datasets[@]}"
do
  output_basedir="$prefix/$ensembl_server/$dataset"

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

  # for verification, we have three possible cases ...
  if [[ -f MD5SUM ]]
  then
    # ... a) standard md5 file
    find . -type f ! -name MD5SUM |
      while read -r file
      do
        file=$(basename "$file")
        awk \
          -v file="$file" \
          '$2 == file' \
          MD5SUM
      done |
      md5sum -c $md5sum_verbosity ||
      bailout 'verification error'

    rm -f MD5SUM
  elif [[ -f CHECKSUMS ]]
  then
    sum_local=.sum_local
    sum_remote=.sum_remote

    # ... b) CHECKSUMS file, to be checked with sum
    find . -type f ! -name CHECKSUMS |
      while read -r file
      do
        file=$(basename "$file")

        sum "$file" |
          awk '{ print $1, $2 }' \
              >> $sum_local

        awk \
          -v file="$file" \
          '$3 == file { print $1, $2 }' \
          CHECKSUMS \
          >> $sum_remote
      done

    diff -q $sum_remote $sum_local &> /dev/null ||
      bailout 'verification error'

    rm -f CHECKSUMS $sum_remote $sum_local
  else
    # ... c) no file for verification at all
    log.warning 'skipping verification: no checksums available'
  fi

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
