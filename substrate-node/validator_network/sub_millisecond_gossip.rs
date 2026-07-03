pub fn gossip_batch_size(tps: u64) -> usize {
    (tps as usize / 100).clamp(64, 4096)
}
