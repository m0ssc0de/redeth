#! /usr/bin/env nix-shell
#! nix-shell -i bash /default.nix
set -eux

STREAM_ID="${STREAM_ID:-mystream}"
GROUP_ID="${GROUP_ID:-mygroup}"
WORKER_ID="${WORKER_ID:-myid}"
INFO_FILE="${WORKER_ID}-JOB"
JOB_LINES=10
declare -A JOB

UPLOADED_SET="uploaded:set"
UPLOADED_STREAM=${UPLOADED_SET}:stream
SORTED_POINTER="sorted"
LAST_ID=$(redis-cli get $SORTED_POINTER); [[ -z "$LAST_ID" ]] && LAST_ID="-1"
BUCKET_NAME="moss-temp"

function readJob() {
    INFO_FILE="${WORKER_ID}-JOB"
    THE_LINE_OF_MSGID=2
    THE_LINE_OF_START=4
    THE_LINE_OF_END=6
    THE_LINE_OF_API=8
    THE_LINE_OF_BUCKET=10
    JOB[MSGID]="$(sed "${THE_LINE_OF_MSGID}q;d" $INFO_FILE)"
    JOB[START]=$(sed "${THE_LINE_OF_START}q;d" $INFO_FILE)
    JOB[END]=$(sed "${THE_LINE_OF_END}q;d" $INFO_FILE)
    JOB[API]=$(sed "${THE_LINE_OF_API}q;d" $INFO_FILE)
    JOB[BUCKET]=$(sed "${THE_LINE_OF_BUCKET}q;d" $INFO_FILE)
}

function processJob() {
    START=${JOB[START]}
    END=${JOB[END]}
    ENDPOINT=${JOB[API]}
    BUCKET_NAME=${JOB[BUCKET]}
    WKDIR=${START}-${END}
    mkdir -p $WKDIR  && cd $WKDIR
    ethereumetl export_blocks_and_transactions --start-block $START --end-block $END --blocks-output blocks.csv --transactions-output transactions.csv --provider-uri $ENDPOINT --max-workers 4 --batch-size 8
    ethereumetl extract_csv_column --input transactions.csv --column hash --output transaction_hashes.txt
    ethereumetl export_receipts_and_logs --transaction-hashes transaction_hashes.txt --receipts-output receipts.csv --logs-output logs.csv --provider-uri $ENDPOINT --max-workers 4 --batch-size 8
    ethereumetl extract_token_transfers --logs logs.csv --output token_transfers.csv --max-workers 10
    ethereumetl extract_csv_column --input receipts.csv --column contract_address --output contract_addresses.txt
    ethereumetl export_contracts --contract-addresses contract_addresses.txt --provider-uri $ENDPOINT --output contracts.csv --max-workers 4 --batch-size 8
    ethereumetl filter_items -i contracts.csv -p "item['is_erc20']=='True' or item['is_erc721']=='True'" | ethereumetl extract_field -f address -o token_addresses.txt
    ethereumetl export_tokens --token-addresses token_addresses.txt --output tokens.csv --provider-uri $ENDPOINT --max-workers 10

    tail -n +2 blocks.csv > blocks.csv.tailp2                   && sort -k 1n -t "," blocks.csv.tailp2 -o blocks.csv
    tail -n +2 contracts.csv > contracts.csv.tailp2             && sort -k 6n -t "," contracts.csv.tailp2 -o contracts.csv
    tail -n +2 receipts.csv > receipts.csv.tailp2               && sort -k 4n -t "," receipts.csv.tailp2 -o receipts.csv
    tail -n +2 token_transfers.csv > token_transfers.csv.tailp2 && sort -k 7n -t "," token_transfers.csv.tailp2 -o token_transfers.csv
    tail -n +2 tokens.csv > tokens.csv.tailp2                   && sort -k 4n -t "," tokens.csv.tailp2 -o tokens.csv
    tail -n +2 transactions.csv > transactions.csv.tailp2       && sort -k 4n -k 5n -t "," transactions.csv.tailp2 -o transactions.csv
    tail -n +2 logs.csv > logs.csv.tailp2                       && sort -k 5n -k 3n -k 1n -t "," logs.csv.tailp2 -o logs.csv

    rm -f *.tailp2 *.txt

    export PartitionPath=DividedBy1_000_000=`printf "%04d" $(($START/1000000))`/DividedBy100_000=`printf "%05d" $(($START/100000))`/DividedBy1_000=`printf "%07d" $(($START/1000))`
    export RangeFileName=`printf "%010d" $START`-`printf "%010d" $END`.csv
    mkdir -p blocks/$PartitionPath contracts/$PartitionPath receipts/$PartitionPath token_transfers/$PartitionPath tokens/$PartitionPath transactions/$PartitionPath logs/$PartitionPath
    mv blocks.csv blocks/$PartitionPath/$RangeFileName
    mv contracts.csv contracts/$PartitionPath/$RangeFileName
    mv receipts.csv receipts/$PartitionPath/$RangeFileName
    mv token_transfers.csv token_transfers/$PartitionPath/$RangeFileName
    mv tokens.csv tokens/$PartitionPath/$RangeFileName
    mv transactions.csv transactions/$PartitionPath/$RangeFileName
    mv logs.csv logs/$PartitionPath/$RangeFileName

    cd ..

    gsutil -m cp -r -n ${WKDIR} gs://${BUCKET_NAME}/cache/

    rm -rf ${WKDIR}
}

function notifySorter() {
    echo "====> "
    START=${JOB[START]}
    END=${JOB[END]}
    ENDPOINT=${JOB[API]}
    BUCKET_NAME=${JOB[BUCKET]}
    WKDIR=${START}-${END}
    redis-cli ZADD $UPLOADED_SET $START ${WKDIR}:$BUCKET_NAME
    redis-cli XADD $UPLOADED_STREAM \* ${WKDIR}:$BUCKET_NAME $START
    echo "=-=-=-=>"
}

# Process pending jobs
until [ "$(redis-cli XREADGROUP GROUP $GROUP_ID $WORKER_ID COUNT 1 STREAMS $STREAM_ID 0 | tee $INFO_FILE | wc -l)" -ne $JOB_LINES ]
do
    echo "GET PENDING JOB & EXEC IT"
    cat $INFO_FILE
    readJob
    processJob
    notifySorter
    redis-cli XACK mystream $GROUP_ID ${JOB[MSGID]}

done

# Get new job and exec it
while true
do
{
    redis-cli XREADGROUP GROUP $GROUP_ID $WORKER_ID BLOCK 0 STREAMS $STREAM_ID \> > $INFO_FILE
    if [ "$(wc -l < $INFO_FILE)" -eq $JOB_LINES ]; then
        echo "GET NEW JOB & EXEC IT"
        cat $INFO_FILE
        readJob
        processJob
        notifySorter
        redis-cli XACK mystream $GROUP_ID ${JOB[MSGID]}
    fi
    
until [ "$(redis-cli XREADGROUP GROUP $GROUP_ID $WORKER_ID COUNT 1 STREAMS $STREAM_ID 0 | tee $INFO_FILE | wc -l)" -ne $JOB_LINES ]
do
    echo "GET PENDING JOB & EXEC IT"
    cat $INFO_FILE
    readJob
    processJob
    notifySorter
    redis-cli XACK mystream $GROUP_ID ${JOB[MSGID]}

done
}
done