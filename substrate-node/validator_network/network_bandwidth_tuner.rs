pub fn tune_bandwidth(mbps: u64, load: f64) -> u64 {
    ((mbps as f64) * (1.0 + load)).min(10_000.0) as u64
}
