#!/bin/bash

# TODO replace echo with `logger -t $(dirname $0) message`

BLAST_DB_DIR=/data/db/blast

BLAST_DB_DATASET=$1
[[ -n $BLAST_DB_DATASET ]] || {
  echo "usage: $(dirname $0) db" >&2
  exit 1
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
  tar xzfvo $i || exit 1
done &&
echo '[blastdl] done, tagging with date and moving ...' &&
sed -i "s/$BLAST_DB_DATASET/$BLAST_DB_DATASET-$BLAST_DB_DATE/g" $BLAST_DB_DATASET.pal &&
for i in $BLAST_DB_DATASET.* ; do
  mv -n $i $BLAST_DB_DIR/${i/$BLAST_DB_DATASET/$BLAST_DB_DATASET-$BLAST_DB_DATE} || exit 1
done &&
echo '[blastdl] now YOU need to remove access right for krausec!'

popd &> /dev/null
