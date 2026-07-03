//! Validator peer registry with bootstrap set.

#[derive(Debug, Clone)]
pub struct PeerRegistry {
    pub bootstrap: Vec<[u8; 32]>,
    pub active: Vec<[u8; 32]>,
}

impl Default for PeerRegistry {
    fn default() -> Self {
        Self {
            bootstrap: vec![[1u8; 32], [2u8; 32], [3u8; 32]],
            active: Vec::new(),
        }
    }
}

impl PeerRegistry {
    pub fn register_active(&mut self, id: [u8; 32]) {
        if !self.active.contains(&id) {
            self.active.push(id);
        }
    }

    pub fn has_quorum(&self, min: usize) -> bool {
        self.active.len() >= min || self.bootstrap.len() >= min
    }
}
