#!/bin/bash

# TODO replace echo with `logger -t $(dirname $0) message`

# ------------------------------------------------------------------------------
# configuration, arguments
# ------------------------------------------------------------------------------

function usage {
  echo "usage: $(dirname $0) dbname dir"
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

# ------------------------------------------------------------------------------
# application functions
# ------------------------------------------------------------------------------

function update_metadata_file {
  case $BLAST_DB_DATASET in
    nr)
      BLAST_DB_METADATA_FILE=$BLAST_DB_DATASET.pal
      ;;

    nt)
      BLAST_DB_METADATA_FILE=$BLAST_DB_DATASET.nal
      ;;
    *)
      echo "[blastdl] [$(date)] unknown database" >&2
      return 1
      ;;
  esac

  sed -e "s/$BLAST_DB_DATASET/$BLAST_DB_DATASET-$BLAST_DB_DATE/g" \
      -i $BLAST_DB_METADATA_FILE
}

# ------------------------------------------------------------------------------
# application
# ------------------------------------------------------------------------------

# download all md5s first, then download all tarballs
echo "[blastdl] [$(date)] starting download ..." >&2
cat << EOF | lftp ftp://ftp.ncbi.nlm.nih.gov
set net:socket-buffer 33554432
mirror -r -P 8 -i "^$BLAST_DB_DATASET\.[0-9]+\.tar\.gz\.md5$" /blast/db $BLAST_DB_DL_DIR
mirror -r -P 8 -i "^$BLAST_DB_DATASET\.[0-9]+\.tar\.gz$"      /blast/db $BLAST_DB_DL_DIR
EOF
echo "[blastdl] [$(date)] done" >&2

pushd $BLAST_DB_DL_DIR &> /dev/null

BLAST_DB_DATE=$(date +%F)

echo "[blastdl] [$(date)] checking md5 ..." >&2 &&
md5sum --check --quiet *.md5 &&
echo "[blastdl] [$(date)] done, extracting ..." >&2 &&
for i in $BLAST_DB_DATASET.*.tar.gz ; do
  tar xzfo $i || exit 1
done &&
echo "[blastdl] [$(date)] done, tagging with date and moving ..." >&2 &&
update_metadata_file &&
for i in $BLAST_DB_DATASET.* ; do
  mv -n $i $BLAST_DB_DIR/${i/$BLAST_DB_DATASET/$BLAST_DB_DATASET-$BLAST_DB_DATE} || exit 1
done &&
echo "[blastdl] [$(date)] done, setting read only ..." >&2 &&
chmod 444 $BLAST_DB_DIR/$BLAST_DB_DATASET-$BLAST_DB_DATE* &&
echo "[blastdl] [$(date)] done." >&2

popd &> /dev/null
