use dotenv::dotenv;
use redis::{Client, Commands};
// use std::arch::x86_64::_mm_extract_epi64;
use std::env;
use std::{thread, time};
use utils::get_block_number;

mod errors;
mod types;
mod utils;

const MINI_PARTITION_SIZE: u64 = 1000;

fn main() -> Result<(), errors::Error> {
    dotenv().ok();

    let chain_entrypoint = env::var("CHAIN_ENTRYPOINT").expect("CHAIN_ENTRYPOINT must be set"); //"https://polygon.api.onfinality.io/rpc?apikey=bb33ca96-9719-497e-bf06-c291ffed46b4"
    let chain_label = env::var("CHAIN_LABEL").expect("CHAIN_LABEL must be set"); //"latest"
    let chain_offset = env::var("CHAIN_OFFSET").expect("CHAIN_OFFSET must be set"); //"50"
    let chain_offset: u64 = chain_offset.parse().unwrap();
    let google_bucket_name =
        env::var("GOOGLE_BUCKET_NAME").expect("GOOGLE_BUCKET_NAME must be set");
    let redis_entrypoint = env::var("REDIS_ENTRYPOINT").expect("REDIS_ENTRYPOINT must be set"); //"redis://127.0.0.1/"
    let project_id = env::var("PROJECT_ID").expect("PROJECT_ID must be set");
    let redis_stream_name = format!("{}-st", project_id);
    let redis_group_name = format!("{}-gp", project_id);
    let redis_key_job_start = format!("{}-job-start", project_id);
    let redis_key_max_job_size = format!("{}-max-job-size", project_id);

    // Connect to Redis
    let client = Client::open(redis_entrypoint)?;
    let mut conn = client.get_connection()?;

    let mut state = types::State {
        start: match conn.get(redis_key_job_start.clone())? {
            Some(v) => v,
            None => 0,
        },
        end: get_block_number(&chain_entrypoint, &chain_label, chain_offset)?,
        max_job_size: match conn.get(redis_key_max_job_size.clone())? {
            Some(v) => v,
            None => 10,
        },
    };
    println!("main state {:#?}", state);

    let _ = redis::cmd("XGROUP")
        .arg("CREATE")
        .arg(redis_stream_name.clone())
        .arg(redis_group_name)
        .arg("$")
        .arg("MKSTREAM")
        .query::<()>(&mut conn);

    while state.start <= state.end {
        state.max_job_size = match conn.get(redis_key_max_job_size.clone())? {
            Some(v) => v,
            None => state.max_job_size,
        };
        let group: types::Group = match conn
            .xinfo_groups::<&str, Vec<types::Group>>(&redis_stream_name.clone())?
            .get(0)
        {
            Some(group) => group.clone(),
            None => {
                println!("No groups found for {}", redis_stream_name);
                break;
            }
        };
        println!(
            "group consumers {}, pending {}, lag {}",
            group.consumers, group.pending, group.lag
        );

        let jobs_cache_size = if group.consumers * 2 < group.lag {
            println!("so many waiting jobs");
            thread::sleep(time::Duration::from_secs(1));
            continue;
        } else {
            group.consumers * 2 - group.lag
        };

        // produce job

        if state.start == state.end {
            println!("no more blocks");
            thread::sleep(time::Duration::from_secs(1));
            if let Ok(update) = get_block_number(&chain_entrypoint, &chain_label, chain_offset) {
                if update > state.end {
                    state.end = update;
                    println!("update to {}", state.end);
                }
            }
            continue;
        }

        for _ in 0..jobs_cache_size {
            if state.start <= state.end {
                let job = types::Job {
                    start: state.start,
                    end: state
                        .end
                        .min((state.start / MINI_PARTITION_SIZE + 1) * MINI_PARTITION_SIZE - 1)
                        .min(state.start + state.max_job_size - 1),
                    endpoint: chain_entrypoint.to_owned(),
                    bucket: google_bucket_name.to_owned(),
                };
                println!("{:#?}", job);
                let job_params = &[
                    ("START", job.start.to_string()),
                    ("END", job.end.to_string()),
                    ("API", job.endpoint),
                    ("BUCKET", job.bucket),
                ];
                conn.xadd(redis_stream_name.clone(), "*", job_params)?;
                state.start = job.end + 1;
                let _ = conn.set(redis_key_job_start.clone(), state.start)?;
            }
        }

        while state.start > state.end {
            if let Ok(update) = get_block_number(&chain_entrypoint, &chain_label, chain_offset) {
                if update > state.end {
                    state.end = update;
                    println!("update to {}", state.end);
                }
            }
            thread::sleep(time::Duration::from_secs(3));
        }
        println!("{:#?}", state);
        thread::sleep(time::Duration::from_secs(3));
    }

    Ok(())
}
