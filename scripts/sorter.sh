## ! /usr/bin/env nix-shell
## ! nix-shell -i bash /default.nix
#!/bin/bash
set -eux

gcloud auth activate-service-account --key-file /gskey/gskey.json
function redis-cmd() {
    # Redis configuration
    local REDIS_HOST="${REDIS_HOST:-localhost}"
    local REDIS_PASSWORD="${REDIS_PASSWORD:-}"

    # Connect to Redis and execute command
    redis-cli -h "$REDIS_HOST" -a "$REDIS_PASSWORD" "$@"
}
PROJECT_ID="${PROJECT_ID}"
UPLOADED_SET="${PROJECT_ID}uploaded:set"
UPLOADED_STREAM=${UPLOADED_SET}:stream
SORTED_POINTER="${PROJECT_ID}sorted"
# BUCKET_NAME="moss-temp"

while true; do
    LAST_ID=$(redis-cmd get $SORTED_POINTER); [[ -z "$LAST_ID" ]] && LAST_ID="-1"
    data=$(redis-cmd ZRANGE $UPLOADED_SET 0 -1)
    [ -z "$data" ] && sleep 1 && continue

    TO_COPY=()
    TO_RM=()
    IFS=$'\n' read -ra array <<< "$data"
    while IFS= read -r element; do
        echo "$element"
        IFS=':' read -r range bucket <<< "$element"
        IFS='-' read -r start end <<< "$range"
        echo "LAST_ID" $LAST_ID "start" $start

        if (( LAST_ID + 1 != start )); then
            # echo "GAPPPP" $LAST_ID $start
            # redis-cli XREAD BLOCK 0 STREAMS $UPLOADED_STREAM "$"
            break
        else
            LAST_ID=$end
            TO_COPY+=("gs://${bucket}/cache/${range}/*")
            TO_RM+=("$element")
            # gsutil -m cp -r -n gs://$bucket/cache/$range/* gs://$bucket/
            # redis-cli ZREM $UPLOADED_SET $data
            # redis-cli SET $SORTED_POINTER $LAST_ID
        fi
    done <<< "$data"

    [ ${#TO_COPY[@]} -eq 0 ] && sleep 1 && continue
    IFS=" " COPY_FROM="${TO_COPY[*]}"
    gsutil -m cp -r -n $COPY_FROM gs://${bucket}
    IFS=" " DEL_IN_SET="${TO_RM[*]}"
    redis-cmd ZREM $UPLOADED_SET $DEL_IN_SET
    redis-cmd SET $SORTED_POINTER $LAST_ID
    # if (( LAST_ID + 1 != start )); then
    #     echo "GAPPPP" $LAST_ID $start
    #     redis-cli XREAD BLOCK 0 STREAMS $UPLOADED_STREAM "$"
    # else
    #     LAST_ID=$end
    #     gsutil -m cp -r -n gs://$bucket/cache/$range/* gs://$bucket/
    #     redis-cli ZREM $UPLOADED_SET $data
    #     redis-cli SET $SORTED_POINTER $LAST_ID
    # fi
done