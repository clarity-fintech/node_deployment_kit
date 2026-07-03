pub fn reputation_score(uptime: f64, slashes: u32) -> f64 {
    (uptime * 100.0) - (slashes as f64 * 10.0)
}
