use reqwest::Error as ReqwestError;
use serde_json::Error as SerdeJsonError;
use redis::RedisError;
use std::num::ParseIntError;

#[derive(Debug)]
pub enum Error {
    Reqwest(ReqwestError),
    SerdeJson(SerdeJsonError),
    MissField(String, String),
    Redis(RedisError),
    ParseInt(ParseIntError),
}

impl From<ReqwestError> for Error {
    fn from(error: ReqwestError) -> Self {
        Error::Reqwest(error)
    }
}

impl From<SerdeJsonError> for Error {
    fn from(error: SerdeJsonError) -> Self {
        Error::SerdeJson(error)
    }
}

impl From<RedisError> for Error {
    fn from(error: RedisError) -> Self {
        Error::Redis(error)
    }
}

impl From<ParseIntError> for Error {
    fn from(error: ParseIntError) -> Self {
        Error::ParseInt(error)
    }
}