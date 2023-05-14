use std::collections::HashMap;

use errors::Error;
use redis::{FromRedisValue, RedisError, ErrorKind};
use redis::{Client, Commands, RedisResult, Value };
use reqwest::get;
use utils::{get_block_number};
use std::{thread, time};



mod types;
mod utils;
mod errors;

const MAX_JOB_SIZE: u64 = 500;
const INIT_FROM: u64 = 13;
const DYNAMIC_FROM: u64 = 1;
const MINI_PARTITION_SIZE: u64 = 1000;
const MY_STREAM: &str = "mystream";

fn main() -> Result<(), errors::Error> {
    println!("hi");

    // let url = "https://polygon.api.onfinality.io/rpc?apikey=bb33ca96-9719-497e-bf06-c291ffed46b4";
    let url = "https://polygon-rpc.com/";
    let bucket = "moss-temp";

//     // Connect to Redis
    let client = Client::open("redis://127.0.0.1/")?;
    let mut conn = client.get_connection()?;

    let mut start = 3;
    let mut end = get_block_number(url, "latest", 0)?;
    println!("main from start {} end {}", start, end);

    let mut con = client.get_connection()?;
    let _ = redis::cmd("XGROUP")
        .arg("CREATE")
        .arg(MY_STREAM)
        .arg("mygroup")
        .arg("$")
        .arg("MKSTREAM")
        .query::<()>(&mut con);

    while start <= end {
        let group : types::Group = match conn.xinfo_groups::<&str, Vec<types::Group>>(MY_STREAM)?.get(0) {
            Some(group) => group.clone(),
            None => {
                println!("No groups found for {}", MY_STREAM);
                break;
            }
        };
        println!("group consumers {}, pending {}, lag {}", group.consumers, group.pending, group.lag);

        let jobs_cache_size = group.consumers * 2 - group.lag;
        if jobs_cache_size <= 0 {
            // works are busy
            println!("so many waiting jobs");
            thread::sleep(time::Duration::from_secs(1));
            continue;
        }

        if start == end {
            println!("no more blocks");
            // end = get_block_number(url, "latest", 0)?;
            thread::sleep(time::Duration::from_secs(1));
            if let Ok(update) = get_block_number(url, "latest", 0) {
                if update > end {
                    end = update;
                    println!("update to {}", end);
                }
            }
            continue;
        }

        let jobs_start = if start == 0 {
            start
        } else {
            start+1
        };
        let jobs_end = (jobs_start + jobs_cache_size * MAX_JOB_SIZE).min((jobs_start/MINI_PARTITION_SIZE+1)*MINI_PARTITION_SIZE - 1).min(end);

        println!("jobs_cache_size {} jobs_start {} jobs_end {} start {} end {}", jobs_cache_size, jobs_start, jobs_end, start, end);

        for i in 0..jobs_cache_size {
            let (job_start, job_end) = if jobs_end != (jobs_start + jobs_cache_size * MAX_JOB_SIZE) {
                (jobs_start, jobs_end)
            } else {
                (jobs_start + i * MAX_JOB_SIZE, jobs_start + i * MAX_JOB_SIZE + MAX_JOB_SIZE - 1)
            };

            let job_params = &[("START", job_start.to_string()), ("END", job_end.to_string()), ("API", url.to_owned()), ("BUCKET", bucket.to_owned())];
            println!("CREATE JOB  {} - {}", job_start, job_end);

            conn.xadd(MY_STREAM, "*", job_params)?;
            start = job_end;
            if jobs_end == job_end {
                // end = start;
                println!("time to break for start {} end {}", start, end);
                break;
            }
        }
        // 1. job slots were used over
        // 2. reach partition limit
        // 3. reach last block

        // println!("need more jobs");
        if let Ok(update) = get_block_number(url, "latest", 0) {
            if update > end {
                end = update;
                println!("update to {}", end);
            }
        }
        thread::sleep(time::Duration::from_secs(1));
        println!("in the end of wile start {} end {}", start, end)
    }

    Ok(())
}
