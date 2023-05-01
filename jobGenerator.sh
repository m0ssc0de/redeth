#!/bin/bash
redis-cli XGROUP CREATE mystream mygroup $ MKSTREAM
redis-cli XADD mystream \* START 0 END 10 API url1
redis-cli XADD mystream \* START 11 END 19 API url1
redis-cli XADD mystream \* START 20 END 29 API url1
redis-cli XADD mystream \* START 30 END 39 API url1
redis-cli XADD mystream \* START 40 END 49 API url1
redis-cli XADD mystream \* START 50 END 59 API url1
redis-cli XADD mystream \* START 60 END 69 API url1