#!/bin/bash

# ------------------------------------------------------------------------------
# configuration, arguments
# ------------------------------------------------------------------------------

function usage {
  echo "usage: bash $0 dbname dir"
}

BLAST_DB_DATASET=$1
[[ -n $BLAST_DB_DATASET ]] || {
  usage >&2
  exit 1
}

BLAST_DB_DIR=$2
[[ -d $BLAST_DB_DIR ]] || {
  usage >&2
  exit 1
}

BLAST_DB_DL_DIR=$(mktemp -d --tmpdir=$BLAST_DB_DIR .blastdl-XXXXXXXXXX)
trap 'rm -rf $BLAST_DB_DL_DIR' EXIT INT TERM

BLAST_DB_DATE=$(date +%F)

# ------------------------------------------------------------------------------
# application functions
# ------------------------------------------------------------------------------

function log.info {
  logger -p user.info -t blastdl "$@"
}

function log.err {
  logger -p user.err -t blastdl "$@"
}

function blastdl.download {
  # download all md5s first, then download all tarballs
  cat << EOF | lftp ftp://ftp.ncbi.nlm.nih.gov
set net:socket-buffer 33554432
mirror -r -P 8 -i "^$BLAST_DB_DATASET\.[0-9]+\.tar\.gz\.md5$" /blast/db $BLAST_DB_DL_DIR
mirror -r -P 8 -i "^$BLAST_DB_DATASET\.[0-9]+\.tar\.gz$"      /blast/db $BLAST_DB_DL_DIR
EOF
}

function blastdl.update.metadata {
  case $BLAST_DB_DATASET in
    nr)
      BLAST_DB_METADATA_FILE=$BLAST_DB_DATASET.pal
      ;;

    nt|refseq_genomic)
      BLAST_DB_METADATA_FILE=$BLAST_DB_DATASET.nal
      ;;
    *)
      log.err "unknown database $BLAST_DB_DATASET"
      return 1
      ;;
  esac

  sed -e "s/$BLAST_DB_DATASET/$BLAST_DB_DATASET-$BLAST_DB_DATE/g" \
      -i $BLAST_DB_METADATA_FILE
}

# ------------------------------------------------------------------------------
# application
# ------------------------------------------------------------------------------

log.info "starting download of $BLAST_DB_DATASET database ..." &&
blastdl.download &&
log.info "... download finished, checking md5 ..." &&
pushd $BLAST_DB_DL_DIR &> /dev/null &&
md5sum --check --quiet *.md5 &&
log.info "... md5 success, extracting ..." &&
for i in $BLAST_DB_DATASET.*.tar.gz ; do
  tar xzfo $i || exit 1
  rm $i $i.md5
done &&
log.info "... extracting finished, tagging with date and moving ..." &&
blastdl.update.metadata &&
for i in $BLAST_DB_DATASET.* ; do
  mv -n $i $BLAST_DB_DIR/${i/$BLAST_DB_DATASET/$BLAST_DB_DATASET-$BLAST_DB_DATE} || exit 1
done &&
log.info "... moving done, setting read only ..." &&
chmod 444 $BLAST_DB_DIR/$BLAST_DB_DATASET-$BLAST_DB_DATE* &&
log.info "... set read only, done." &&
popd &> /dev/null
