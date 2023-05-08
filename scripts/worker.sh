#!/bin/bash
set -eux

STREAM_ID="${STREAM_ID:-mystream}"
GROUP_ID="${GROUP_ID:-mygroup}"
WORKER_ID="${WORKER_ID:-myid}"
JOB_LINES=8
THE_LINE_OF_MSGID=2

# Process pending jobs
until [ "$(redis-cli XREADGROUP GROUP $GROUP_ID $WORKER_ID COUNT 1 STREAMS $STREAM_ID 0 | tee JOB | wc -l)" -ne $JOB_LINES ]
do
    echo "GET PENDING JOB & EXEC IT"
    cat JOB
    redis-cli XACK mystream $GROUP_ID $(sed "${THE_LINE_OF_MSGID}q;d" JOB)
done

# Get new job and exec it
while true
do
{
    redis-cli XREADGROUP GROUP $GROUP_ID $WORKER_ID COUNT 1 STREAMS $STREAM_ID \> > JOB
    if [ "$(wc -l < JOB)" -eq $JOB_LINES ]; then
        echo "GET NEW JOB & EXEC IT"
        cat JOB
        redis-cli XACK mystream $GROUP_ID $(sed "${THE_LINE_OF_MSGID}q;d" JOB)
    fi
}
done