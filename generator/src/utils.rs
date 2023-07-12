use serde_json::Value as jsonValue;
use super::errors::Error;

pub fn get_block_number(url: &str, tag: &str, offset: u64) -> Result<u64, Error> {
    let client = reqwest::blocking::Client::new();
    let response = client
        .post(url)
        .header("Content-type", "application/json")
        .body(format!("{{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"{}\", false],\"id\":1}}", tag))
        .send()?;

    let json: jsonValue = response.json()?;
    let number = json.get("result").ok_or(Error::MissField("result".to_string(), "".to_string()))?
        .get("number").ok_or(Error::MissField("number".to_string() , "".to_string()))?.to_string();
    let number = u64::from_str_radix(&number.trim_matches('"')[2..], 16)?;
    println!("UPDATE FROM NODE {}", number-offset);
    Ok(number-offset)
}