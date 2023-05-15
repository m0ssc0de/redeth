#!/bin/bash
set -eux

UPLOADED_SET="uploaded:set"
UPLOADED_STREAM=${UPLOADED_SET}:stream
SORTED_POINTER="sorted"
LAST_ID=$(redis-cli get $SORTED_POINTER); [[ -z "$LAST_ID" ]] && LAST_ID="-1"
# BUCKET_NAME="moss-temp"

while true; do
    data=$(redis-cli ZRANGE $UPLOADED_SET 0 0)
    [ -z "$data" ] && sleep 1 && continue
    IFS=':' read -r range bucket <<< "$data"
    IFS='-' read -r start end <<< "$range"
    if (( LAST_ID + 1 != start )); then
        echo "GAPPPP" $LAST_ID $start
        redis-cli XREAD BLOCK 0 STREAMS $UPLOADED_STREAM "$"
    else
        LAST_ID=$end
        gsutil -m cp -r -n gs://$bucket/cache/$range/* gs://$bucket/
        redis-cli ZREM $UPLOADED_SET $data
        redis-cli SET $SORTED_POINTER $LAST_ID
    fi
done