use std::collections::HashMap;

use redis::{FromRedisValue, RedisError, ErrorKind};
use redis::{Client, Commands, RedisResult, Value };
pub struct Group {
    pub name: String,
    pub consumers: u32,
    pub pending: u32,
}

impl FromRedisValue for Group {
    fn from_redis_value(v: &redis::Value) -> RedisResult<Self> {
        let hm = HashMap::<String, Value>::from_redis_value(v)?;
        let name = hm.get("name").and_then(|v| {
            Some(String::from_redis_value(v))
        }).unwrap()?;
        let consumers = hm.get("consumers").and_then(|v| {
            Some(u32::from_redis_value(v))
        }).unwrap()?;
        let pending = hm.get("pending").and_then(|v| {
            Some(u32::from_redis_value(v))
        }).unwrap()?;
        Ok(Group{name, consumers, pending})
    }
}