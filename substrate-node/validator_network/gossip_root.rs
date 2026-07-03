//! Gossip root hash chain for validator mesh.

use sha2::{Digest, Sha256};

#[derive(Debug, Default)]
pub struct GossipRoot {
    pub roots: Vec<[u8; 32]>,
}

impl GossipRoot {
    pub fn append(&mut self, payload: &[u8]) -> [u8; 32] {
        let mut h = Sha256::new();
        h.update(payload);
        if let Some(prev) = self.roots.last() {
            h.update(prev);
        }
        let out = h.finalize();
        let mut root = [0u8; 32];
        root.copy_from_slice(&out);
        self.roots.push(root);
        root
    }

    pub fn height(&self) -> usize {
        self.roots.len()
    }
}
