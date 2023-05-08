#!/bin/bash
STREAM_ID="${STREAM_ID:-mystream}"
GROUP_ID="${GROUP_ID:-mygroup}"

redis-cli XGROUP CREATE $STREAM_ID $GROUP_ID $ MKSTREAM
redis-cli XADD mystream \* START 0 END 10 API url1
redis-cli XADD mystream \* START 11 END 19 API url1
redis-cli XADD mystream \* START 20 END 29 API url1
redis-cli XADD mystream \* START 30 END 39 API url1
redis-cli XADD mystream \* START 40 END 49 API url1
redis-cli XADD mystream \* START 50 END 59 API url1
redis-cli XADD mystream \* START 60 END 69 API url1

# SET BLOCK_START 0
# SET BLOCK_UNTIL 0
# SET JOB_START 0
# SET JOB_UNTIL 0
# SET UPLOAD_TO 0

# # while true {
#     # update BLOCK_UNTIL
#     SET BLOCK_UNTIL 101
# # }

# function generateJobs1by1 () {
#     JOB_UNTIL=$(redis-cli GET JOB_UNTIL)
#     BLOCK_UNTIL=$(redis-cli GET BLOCK_UNTIL)
#     if ($JOB_UNTIL < $BLOCK_UNTIL) {
#         redis-cli XADD mystream \* START $JOB_UNTIL END $JOB_UNTIL API url1
#         redis-cli incr JOB_UNTIL
#     }
# }

# function generateJobsBatch () {
#     JOB_UNTIL=$(redis-cli GET JOB_UNTIL)
#     BLOCK_UNTIL=$(redis-cli GET BLOCK_UNTIL)
#     if ($BLOCK_UNTIL - $JOB_UNTIL)/$BATCH_SIZE
# }
# # 107