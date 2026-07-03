pub fn bootstrap_validators(count: usize) -> Vec<String> {
    (0..count)
        .map(|i| format!("validator-{}", i))
        .collect()
}
