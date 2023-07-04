##! /usr/bin/env nix-shell
##! nix-shell -i bash /default.nix
#!/bin/bash
set -eux

function redis-cmd() {
    # Redis configuration
    local REDIS_HOST="${REDIS_HOST:-localhost}"
    local REDIS_PASSWORD="${REDIS_PASSWORD:-}"

    # Connect to Redis and execute command
    redis-cli -h "$REDIS_HOST" -a "$REDIS_PASSWORD" "$@"
}
PROJECT_ID="${PROJECT_ID}"
STREAM_ID="${PROJECT_ID}-st"
GROUP_ID="${PROJECT_ID}-gp"
WORKER_ID="${HOSTNAME:-myid}"
INFO_FILE="${WORKER_ID}-JOB"
JOB_LINES=10
ENABLE_BACKUP=${ENABLE_BACKUP:-false}
ENDPOINT_BACKUP=${ENDPOINT_BACKUP:-https://polygon-rpc.com}
ENDPOINT_BACKUP_TAG=${ENDPOINT_BACKUP_TAG:-polygon.api.onfinality.io}
declare -A JOB

UPLOADED_SET="${PROJECT_ID}uploaded:set"
UPLOADED_STREAM="${UPLOADED_SET}:stream"
SORTED_POINTER="${PROJECT_ID}sorted"
LAST_ID=$(redis-cmd get $SORTED_POINTER); [[ -z "$LAST_ID" ]] && LAST_ID="-1"
# BUCKET_NAME="${BUCKET_NAME}"

gcloud auth activate-service-account --key-file /gskey/gskey.json

DB_HOST=${DB_HOST:-cockroachdb.cockroachdb}
DB_PORT=${DB_PORT:-26257}
DATABASE=${DATABASE:-postgres}
WORKER=$WORKER_ID
DB_SCHEMA=${DB_SCHEMA:-polygon-raw-0506}
DB_DATA_TABLE_LOGS=${DB_DATA_TABLE_LOGS:-evm_logs_tmp}
DB_DATA_TABLE_TXS=${DB_DATA_TABLE_TXS:-evm_transactions_tmp}
CREDENTIALS=${CREDENTIALS}

load_logs() {

  SQL="CREATE TABLE IF NOT EXISTS \"$DB_SCHEMA\".evm_logs_tmp_${WORKER//-/_} (
          log_index BIGINT NULL,
          transaction_hash VARCHAR NULL,
          transaction_index INT8 NULL,
          address VARCHAR NULL,
          data STRING NULL,
          topics STRING NULL,
          block_timestamp TIMESTAMP NULL,
          block_number BIGINT NULL,
          block_hash VARCHAR NULL
  );"
  OUTPUT=$(psql -h "$DB_HOST" -p "$DB_PORT" -d "$DATABASE" -c "$SQL")
  echo $OUTPUT

  SQL="TRUNCATE table \"$DB_SCHEMA\".evm_logs_tmp_${WORKER//-/_}"
  OUTPUT=$(psql -h "$DB_HOST" -p "$DB_PORT" -d "$DATABASE" -c "$SQL")
  echo $OUTPUT
  date
  
  SQL="
  IMPORT INTO \"$DB_SCHEMA\".evm_logs_tmp_${WORKER//-/_} (log_index,transaction_hash,transaction_index,block_hash,block_number,address,data,topics)
      CSV DATA (
          'gs://$LOGS_CSVPATH?CREDENTIALS=$CREDENTIALS'
      );
  "
  OUTPUT=$(psql -h "$DB_HOST" -p "$DB_PORT" -d "$DATABASE" -c "$SQL")
  echo $OUTPUT
  
  
  SQL="
  UPSERT INTO \"$DB_SCHEMA\".$DB_DATA_TABLE_LOGS (
      id,
      address,
      block_height,
      topics0,
      topics1,
      topics2,
      topics3
  )
  SELECT
      block_number || '-' || log_index,
      address,
      block_number,
      split_part(topics, ',', 1),
      split_part(topics, ',', 2),
      split_part(topics, ',', 3),
      split_part(topics, ',', 4)
  FROM \"$DB_SCHEMA\".evm_logs_tmp_${WORKER//-/_};
  "
  OUTPUT=$(psql -h "$DB_HOST" -p "$DB_PORT" -d "$DATABASE" -c "$SQL")
  echo $OUTPUT
  date

  SQL="TRUNCATE table \"$DB_SCHEMA\".evm_logs_tmp_${WORKER//-/_}"
  OUTPUT=$(psql -h "$DB_HOST" -p "$DB_PORT" -d "$DATABASE" -c "$SQL")
  echo $OUTPUT
  date
}

load_transactions() {

  SQL="CREATE TABLE IF NOT EXISTS \"$DB_SCHEMA\".evm_transactions_tmp_${WORKER//-/_} (
         hash VARCHAR NULL,
         nonce BIGINT NULL,
         transaction_index INT8 NULL,
         from_address VARCHAR NULL,
         to_address VARCHAR NULL,
         value DECIMAL NULL,
         gas BIGINT NULL,
         gas_price BIGINT NULL,
         input STRING NULL,
         block_timestamp VARCHAR NULL,
         block_number BIGINT NULL,
         block_hash VARCHAR NULL,
         max_fee_per_gas VARCHAR NULL,
         max_priority_fee_per_gas VARCHAR NULL,
         transaction_type BIGINT NULL
  );"
  OUTPUT=$(psql -h "$DB_HOST" -p "$DB_PORT" -d "$DATABASE" -c "$SQL")
  echo $OUTPUT

  SQL="TRUNCATE table \"$DB_SCHEMA\".evm_transactions_tmp_${WORKER//-/_}"
  OUTPUT=$(psql -h "$DB_HOST" -p "$DB_PORT" -d "$DATABASE" -c "$SQL")
  echo $OUTPUT
  date
  
  SQL="
  IMPORT INTO \"$DB_SCHEMA\".evm_transactions_tmp_${WORKER//-/_} (hash,nonce,block_hash,block_number,transaction_index,from_address,to_address,value,gas,gas_price,input,block_timestamp,max_fee_per_gas,max_priority_fee_per_gas,transaction_type)
      CSV DATA (
          'gs://$TXS_CSVPATH?CREDENTIALS=$CREDENTIALS'
      );
  "
  OUTPUT=$(psql -h "$DB_HOST" -p "$DB_PORT" -d "$DATABASE" -c "$SQL")
  echo $OUTPUT
  
  
  SQL="
  UPSERT INTO \"$DB_SCHEMA\".$DB_DATA_TABLE_TXS (
      id,
      tx_hash,
      \"from\",
      \"to\",
      func,
      block_height,
      success
  )
  SELECT
      block_number || '-' || transaction_index,
      \"hash\",
      from_address,
      COALESCE(to_address, ''),
      SUBSTRING(input, 1, 10),
      block_number,
      CAST(1 AS BOOL)
  FROM \"$DB_SCHEMA\".evm_transactions_tmp_${WORKER//-/_};
  "
  OUTPUT=$(psql -h "$DB_HOST" -p "$DB_PORT" -d "$DATABASE" -c "$SQL")
  echo $OUTPUT
  date

  SQL="TRUNCATE table \"$DB_SCHEMA\".evm_transactions_tmp_${WORKER//-/_}"
  OUTPUT=$(psql -h "$DB_HOST" -p "$DB_PORT" -d "$DATABASE" -c "$SQL")
  echo $OUTPUT
  date
}


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
    if [ "$ENABLE_BACKUP" = "true" ]; then
        if [ "`cut -d',' -f6 transactions.csv | grep -m 1 0x0000000000000000000000000000000000000000`" == "0x0000000000000000000000000000000000000000" ]; then
          ethereumetl export_receipts_and_logs --transaction-hashes transaction_hashes.txt --receipts-output receipts.csv --logs-output logs.csv --provider-uri $ENDPOINT_BACKUP --max-workers 4 --batch-size 8
        else
          ethereumetl export_receipts_and_logs --transaction-hashes transaction_hashes.txt --receipts-output receipts.csv --logs-output logs.csv --provider-uri $ENDPOINT --max-workers 4 --batch-size 8
        fi
    else
        ethereumetl export_receipts_and_logs --transaction-hashes transaction_hashes.txt --receipts-output receipts.csv --logs-output logs.csv --provider-uri $ENDPOINT --max-workers 4 --batch-size 8
    fi
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

    LOGS_CSVPATH="${BUCKET_NAME}/cache/${WKDIR}/logs/$PartitionPath/$RangeFileName"
    TXS_CSVPATH="${BUCKET_NAME}/cache/${WKDIR}/transactions/$PartitionPath/$RangeFileName"
    load_logs
    load_transactions

    rm -rf ${WKDIR}
}

function notifySorter() {
    echo "====> "
    START=${JOB[START]}
    END=${JOB[END]}
    ENDPOINT=${JOB[API]}
    BUCKET_NAME=${JOB[BUCKET]}
    WKDIR=${START}-${END}
    redis-cmd ZADD $UPLOADED_SET $START ${WKDIR}:$BUCKET_NAME
    redis-cmd XADD $UPLOADED_STREAM \* ${WKDIR}:$BUCKET_NAME $START
    echo "=-=-=-=>"
}

# Process pending jobs
until [ "$(redis-cmd XREADGROUP GROUP $GROUP_ID $WORKER_ID COUNT 1 STREAMS $STREAM_ID 0 | tee $INFO_FILE | wc -l)" -ne $JOB_LINES ]
do
    echo "GET PENDING JOB & EXEC IT"
    cat $INFO_FILE
    readJob
    processJob
    notifySorter
    redis-cmd XACK $STREAM_ID $GROUP_ID ${JOB[MSGID]}

done

# Get new job and exec it
while true
do
{
    redis-cmd XREADGROUP GROUP $GROUP_ID $WORKER_ID BLOCK 0 STREAMS $STREAM_ID \> > $INFO_FILE
    if [ "$(wc -l < $INFO_FILE)" -eq $JOB_LINES ]; then
        echo "GET NEW JOB & EXEC IT"
        cat $INFO_FILE
        readJob
        processJob
        notifySorter
        redis-cmd XACK $STREAM_ID $GROUP_ID ${JOB[MSGID]}
    fi

until [ "$(redis-cmd XREADGROUP GROUP $GROUP_ID $WORKER_ID COUNT 1 STREAMS $STREAM_ID 0 | tee $INFO_FILE | wc -l)" -ne $JOB_LINES ]
do
    echo "GET PENDING JOB & EXEC IT"
    cat $INFO_FILE
    readJob
    processJob
    notifySorter
    redis-cmd XACK $STREAM_ID $GROUP_ID ${JOB[MSGID]}

done
}
done
