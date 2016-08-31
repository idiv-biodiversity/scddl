#!/bin/bash

# TODO replace echo with `logger -t $(dirname $0) message`
# TODO clean up if not successful

BLAST_DB_DIR=/data/db/blast

BLAST_DB_DATASET=$1
[[ -n $BLAST_DB_DATASET ]] || {
  echo "usage: $(dirname $0) db" >&2
  exit 1
}

function update_metadata_file {
  case $BLAST_DB_DATASET in
    nr)
      BLAST_DB_METADATA_FILE=$BLAST_DB_DATASET.pal
      ;;

    nt)
      BLAST_DB_METADATA_FILE=$BLAST_DB_DATASET.nal
      ;;
    *)
      echo '[blastdl] unknown database' >&2
      return 1
      ;;
  esac

  sed -e "s/$BLAST_DB_DATASET/$BLAST_DB_DATASET-$BLAST_DB_DATE/g" \
      -i $BLAST_DB_METADATA_FILE
}

# download all md5s first, then download all tarballs
echo '[blastdl] starting download ...'
cat << EOF | lftp ftp://ftp.ncbi.nlm.nih.gov
set net:socket-buffer 33554432
mirror -r -P 8 -i "^$BLAST_DB_DATASET\.[0-9]+\.tar\.gz\.md5$" /blast/db $BLAST_DB_DIR/dl
mirror -r -P 8 -i "^$BLAST_DB_DATASET\.[0-9]+\.tar\.gz$"      /blast/db $BLAST_DB_DIR/dl
EOF
echo '[blastdl] done'

pushd $BLAST_DB_DIR/dl &> /dev/null

BLAST_DB_DATE=$(date +%F)

echo '[blastdl] checking md5 ...' &&
md5sum -c *.md5 &&
echo '[blastdl] done, extracting ...' &&
for i in $BLAST_DB_DATASET.*.tar.gz ; do
  tar xzfo $i || exit 1
done &&
echo '[blastdl] done, tagging with date and moving ...' &&
update_metadata_file &&
for i in $BLAST_DB_DATASET.* ; do
  mv -n $i $BLAST_DB_DIR/${i/$BLAST_DB_DATASET/$BLAST_DB_DATASET-$BLAST_DB_DATE} || exit 1
done &&
echo '[blastdl] now YOU need to remove access right for krausec!'

popd &> /dev/null
