//! Sub-millisecond peer heartbeat tracker.

use super::peer_table::PeerTable;

#[derive(Debug, Default)]
pub struct PeerHeartbeat {
    pub table: PeerTable,
}

impl PeerHeartbeat {
    pub fn beat(&mut self, id: [u8; 32], endpoint: &str, epoch: u64) {
        self.table.upsert(id, endpoint, epoch);
    }

    pub fn alive_count(&self, _current_epoch: u64, _max_age: u64) -> usize {
        self.table.count()
    }

    pub fn registered(&self) -> usize {
        self.table.count()
    }
}
