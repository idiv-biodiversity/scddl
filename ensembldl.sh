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
fi

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

  cat << EOF | lftp ftp://ftp.ensembl.org
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
  output_basedir="$prefix/ensembl/$dataset"

  output_dir="$output_basedir/$download_date"

  if [[ -e $output_dir ]]
  then
    log.info "skipping $dataset: already exists"
    continue
  fi

  [[ $verbose == yes ]] &&
    log.info "starting download of $dataset"
  download ||
    bailout 'download failed'

  [[ $verbose == yes ]] &&
    log.info "checking md5 checksums"

  pushd "$tmpdir" &> /dev/null

  #ensembl sometimes has 3 cases for checksums: 
  # - MD5SUM file (that need to be checked with md5sum) 
  # - CHKSUMS file (to be checked with sum) 
  # - no checksum at all
  if [[ -f MD5SUM ]]; then
    find . -name "*gz" | while read -r file
    do
      grep "$(basename "$file" .gz)" MD5SUM
    done | md5sum -c --quiet || bailout 'verification error'
    rm MD5SUM
  elif [[ -f CHECKSUMS ]]; then
    # extract checksum (1st 2 columns) from CHECKSUMS 
    # get checksum for the downloaded files (note sum does not 
    # print 3rd column: filename when called for single files)
    find . -name "*gz" | while read -r file
    do
      grep "$(basename "$file" .gz)" CHECKSUMS | awk '{print $1,$2}' >> _REMOTECHKSUM
      sum "$file" | awk '{print $1,$2}'>> _LOCALCHKSUM 
    done 
    diff -q _REMOTECHKSUM _LOCALCHKSUM ||
      bailout 'verification error'
    rm CHECKSUMS _REMOTECHKSUM _LOCALCHKSUM
  else
    log.info "checksums unavailable -> skipping verification"
  fi

  [[ $verbose == yes ]] &&
    log.info "extracting files"

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
        bailout << EOF
do not recognize file type, please open issue for support:
  https://github.com/idiv-biodiversity/scddl/issues
EOF
        ;;
    esac
  done < <(find . -type f)

  popd &> /dev/null

  [[ $verbose == yes ]] &&
    log.info "moving from tmp dir to final destination"

  mkdir -p "$(dirname "$output_dir")"

  mv -n "$tmpdir" "$output_dir" ||
    bailout "moving failed"

  chmod -R +r "$output_dir"
done

if [[ $verbose == yes ]]
then
  log.info "done"
fi
