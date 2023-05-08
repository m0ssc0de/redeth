use std::collections::HashMap;

use redis::{FromRedisValue, RedisError, ErrorKind};
use redis::{Client, Commands, RedisResult, Value };
use std::{thread, time};


mod types;

fn main() -> RedisResult<()> {
    // Connect to Redis
    let client = Client::open("redis://127.0.0.1/")?;
    let mut conn = client.get_connection()?;
    let stream_name = "mystream";
    let group_name = "mygroup";

    loop {
        let res_group : Vec<types::Group>= conn.xinfo_groups("mystream")?;
        let group = res_group.get(0).unwrap();
        if group.consumers * 2 > group.pending {
            println!("need more jobs")
        }
        thread::sleep(time::Duration::from_secs(10));
    }
    // Ok(())
}