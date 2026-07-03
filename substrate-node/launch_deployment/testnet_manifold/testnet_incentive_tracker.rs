pub fn track_uptime(validator: &str, blocks: u64) -> (String, u64) {
    (validator.to_string(), blocks)
}
