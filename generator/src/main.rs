use std::collections::HashMap;

use redis::{FromRedisValue, RedisError, ErrorKind};
use redis::{Client, Commands, RedisResult, Value };
use std::{thread, time};


mod types;

const MAX_JOB_SIZE: u32 = 10;
const INIT_FROM: u32 = 13;
const DYNAMIC_FROM: u32 = 1;
const MINI_PARTITION_SIZE: u32 = 1000;
const MY_STREAM: &str = "mystream";

    fn main() -> RedisResult<()> {

//     // Connect to Redis
    let client = Client::open("redis://127.0.0.1/")?;
    let mut conn = client.get_connection()?;

    let mut start = INIT_FROM;
    let end = 1234;

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


        let jobs_start = start;
        let jobs_end = (jobs_start + jobs_cache_size * MAX_JOB_SIZE).min((jobs_start/MINI_PARTITION_SIZE+1)*MINI_PARTITION_SIZE - 1).min(end);

        println!("jobs_cache_size {} jobs_start {} jobs_end {}", jobs_cache_size, jobs_start, jobs_end);

        for i in 0..jobs_cache_size {
            if jobs_end != (jobs_start + jobs_cache_size * MAX_JOB_SIZE) {
                let job_start = jobs_start;
                let job_end = jobs_end;
                let job_params = &[("START", job_start.to_string()), ("END", job_end.to_string()), ("API", "url1".to_string())];
                println!("reach line");
                println!("START {} END {}", job_start, job_end);

                conn.xadd(MY_STREAM, "*", job_params)?;
                start = job_end + 1;
                break
            }
            let job_start = jobs_start + i * MAX_JOB_SIZE;
            let job_end = job_start + MAX_JOB_SIZE - 1;
            let job_params = &[("START", job_start.to_string()), ("END", job_end.to_string()), ("API", "url1".to_string())];
                println!("START {} END {}", job_start, job_end);
            conn.xadd(MY_STREAM, "*", job_params)?;
            start = job_end + 1;
        }
        println!("need more jobs");
        thread::sleep(time::Duration::from_secs(1));
    }

    Ok(())
}
