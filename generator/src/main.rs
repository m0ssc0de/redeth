
use redis::{Client, Commands };
use utils::{get_block_number};
use std::{thread, time};
use dotenv::dotenv;
use std::env;



mod types;
mod utils;
mod errors;

// const MAX_JOB_SIZE: u64 = 2;
const MINI_PARTITION_SIZE: u64 = 1000;

fn main() -> Result<(), errors::Error> {
    dotenv().ok();

    let chain_entrypoint = env::var("CHAIN_ENTRYPOINT").expect("CHAIN_ENTRYPOINT must be set");//"https://polygon.api.onfinality.io/rpc?apikey=bb33ca96-9719-497e-bf06-c291ffed46b4"
    let google_bucket_name = env::var("GOOGLE_BUCKET_NAME").expect("GOOGLE_BUCKET_NAME must be set");
    let redis_entrypoint = env::var("REDIS_ENTRYPOINT").expect("REDIS_ENTRYPOINT must be set");//"redis://127.0.0.1/"
    let project_id = env::var("PROJECT_ID").expect("PROJECT_ID must be set");
    let redis_stream_name = format!("{}-st", project_id);
    let redis_group_name = format!("{}-gp", project_id);
    let redis_key_job_start = format!("{}-job-start", project_id);
    let redis_key_max_job_size = format!("{}-max-job-size", project_id);

    println!("hi");

    // let url = "https://polygon.api.onfinality.io/rpc?apikey=bb33ca96-9719-497e-bf06-c291ffed46b4";
    // let url = "https://polygon-rpc.com/";
    // let bucket = "moss-temp";

//     // Connect to Redis
    let client = Client::open(redis_entrypoint)?;
    let mut conn = client.get_connection()?;

    // let mut start = 42719300;
    let mut start: u64 = match conn.get(redis_key_job_start.clone())? {
        Some(v) => {v},
        None => {0},
    };
    let mut end = get_block_number(&chain_entrypoint, "latest", 0)?;
    println!("main from start {} end {}", start, end);

    let mut max_job_size = 10;

    // let mut con = client.get_connection()?;
    let _ = redis::cmd("XGROUP")
        .arg("CREATE")
        .arg(redis_stream_name.clone())
        .arg(redis_group_name)
        .arg("$")
        .arg("MKSTREAM")
        .query::<()>(&mut conn);

    while start <= end {
        println!("{}", "start while");
        max_job_size = match conn.get(redis_key_max_job_size.clone())? {
            Some(v) => v,
            None => max_job_size,
        };
        let group : types::Group = match conn.xinfo_groups::<&str, Vec<types::Group>>(&redis_stream_name.clone())?.get(0) {
            Some(group) => group.clone(),
            None => {
                println!("No groups found for {}", redis_stream_name);
                break;
            }
        };
        println!("group consumers {}, pending {}, lag {}", group.consumers, group.pending, group.lag);

        let jobs_cache_size = if group.consumers * 2 < group.lag {
            println!("so many waiting jobs");
            thread::sleep(time::Duration::from_secs(1));
            continue;
        } else {
            group.consumers * 2 - group.lag
        };

        if start == end {
            println!("no more blocks");
            // end = get_block_number(url, "latest", 0)?;
            thread::sleep(time::Duration::from_secs(1));
            if let Ok(update) = get_block_number(&chain_entrypoint, "latest", 0) {
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
        let jobs_end = (jobs_start + jobs_cache_size * max_job_size).min((jobs_start/MINI_PARTITION_SIZE+1)*MINI_PARTITION_SIZE - 1).min(end);

        println!("jobs_cache_size {} jobs_start {} jobs_end {} start {} end {}", jobs_cache_size, jobs_start, jobs_end, start, end);

        for i in 0..jobs_cache_size {
            let (job_start, job_end) = if jobs_end != (jobs_start + jobs_cache_size * max_job_size) {
                (jobs_start, jobs_end)
            } else {
                (jobs_start + i * max_job_size, jobs_start + i * max_job_size + max_job_size - 1)
            };

            let job_params = &[("START", job_start.to_string()), ("END", job_end.to_string()), ("API",chain_entrypoint.to_owned()), ("BUCKET", google_bucket_name.to_owned())];
            println!("CREATE JOB  {} - {}", job_start, job_end);

            conn.xadd(redis_stream_name.clone(), "*", job_params)?;
            start = job_end;
            let _ = conn.set(redis_key_job_start.clone(), start)?;
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
        if let Ok(update) = get_block_number(&chain_entrypoint, "latest", 0) {
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
