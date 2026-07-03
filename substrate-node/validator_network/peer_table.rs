//! Validator peer table.

use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct PeerRecord {
    pub id: [u8; 32],
    pub endpoint: String,
    pub last_seen_epoch: u64,
}

#[derive(Debug, Default)]
pub struct PeerTable {
    peers: HashMap<[u8; 32], PeerRecord>,
}

impl PeerTable {
    pub fn upsert(&mut self, id: [u8; 32], endpoint: &str, epoch: u64) {
        self.peers.insert(
            id,
            PeerRecord {
                id,
                endpoint: endpoint.to_string(),
                last_seen_epoch: epoch,
            },
        );
    }

    pub fn count(&self) -> usize {
        self.peers.len()
    }

    pub fn is_stale(&self, id: &[u8; 32], current_epoch: u64, max_age: u64) -> bool {
        self.peers
            .get(id)
            .map(|p| current_epoch.saturating_sub(p.last_seen_epoch) > max_age)
            .unwrap_or(true)
    }
}
