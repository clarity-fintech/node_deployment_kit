pub fn filter_sybil(connection_count: u32, threshold: u32) -> bool {
    connection_count > threshold
}
