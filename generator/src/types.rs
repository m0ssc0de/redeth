use std::collections::HashMap;

use redis::{FromRedisValue, RedisError, ErrorKind};
use redis::{Client, Commands, RedisResult, Value };

#[derive(Clone)]
pub struct Group {
    pub name: String,
    pub consumers: u64,
    pub pending: u64,
    pub lag: u64,
}

impl FromRedisValue for Group {
    fn from_redis_value(v: &redis::Value) -> RedisResult<Self> {
        let hm = HashMap::<String, Value>::from_redis_value(v)?;
        let name = hm.get("name").and_then(|v| {
            Some(String::from_redis_value(v))
        }).unwrap()?;
        let consumers = hm.get("consumers").and_then(|v| {
            Some(u64::from_redis_value(v))
        }).unwrap()?;
        let pending = hm.get("pending").and_then(|v| {
            Some(u64::from_redis_value(v))
        }).unwrap()?;
        let lag = hm.get("lag").and_then(|v| {
            Some(u64::from_redis_value(v))
        }).unwrap()?;
        Ok(Group{name, consumers, pending, lag})
    }
}