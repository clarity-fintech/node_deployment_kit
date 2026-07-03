//! Persistent node registry for L06 Node Governance (free + sovereign tiers).

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeRecord {
    pub node_id: String,
    pub tier: String,
    pub customer_id: Option<String>,
    pub registered_at: u64,
    pub last_heartbeat_at: Option<u64>,
    pub version: Option<String>,
    pub uptime_secs: Option<u64>,
    pub heartbeat_interval_secs: u64,
}

fn registry_path() -> PathBuf {
    std::env::var("CLRTY_ROOT")
        .map(|r| PathBuf::from(r).join("var/monetization/node_registry.json"))
        .unwrap_or_else(|_| PathBuf::from("var/monetization/node_registry.json"))
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn load_registry_file() -> HashMap<String, NodeRecord> {
    let p = registry_path();
    if let Ok(data) = std::fs::read_to_string(&p) {
        if let Ok(map) = serde_json::from_str::<HashMap<String, NodeRecord>>(&data) {
            return map;
        }
    }
    HashMap::new()
}

fn save_registry(map: &HashMap<String, NodeRecord>) -> std::io::Result<()> {
    let p = registry_path();
    if let Some(parent) = p.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(&p, serde_json::to_string_pretty(map).unwrap_or_default())
}

pub fn register_node(
    node_id: &str,
    tier: &str,
    customer_id: Option<String>,
    heartbeat_interval_secs: u64,
) -> std::io::Result<NodeRecord> {
    let mut map = load_registry_file();
    let record = NodeRecord {
        node_id: node_id.to_string(),
        tier: tier.to_string(),
        customer_id,
        registered_at: now_secs(),
        last_heartbeat_at: None,
        version: None,
        uptime_secs: None,
        heartbeat_interval_secs,
    };
    map.insert(node_id.to_string(), record.clone());
    save_registry(&map)?;
    Ok(record)
}

pub fn record_heartbeat(
    node_id: &str,
    version: Option<String>,
    uptime_secs: Option<u64>,
) -> Result<NodeRecord, String> {
    let mut map = load_registry_file();
    let rec = map
        .get_mut(node_id)
        .ok_or_else(|| format!("node not registered: {node_id}"))?;
    rec.last_heartbeat_at = Some(now_secs());
    rec.version = version;
    rec.uptime_secs = uptime_secs;
    let out = rec.clone();
    save_registry(&map).map_err(|e| e.to_string())?;
    Ok(out)
}

pub fn get_node(node_id: &str) -> Option<NodeRecord> {
    load_registry_file().get(node_id).cloned()
}

pub fn list_nodes() -> Vec<NodeRecord> {
    let mut v: Vec<_> = load_registry_file().into_values().collect();
    v.sort_by(|a, b| a.node_id.cmp(&b.node_id));
    v
}

pub fn registry_summary() -> Value {
    let nodes = list_nodes();
    json!({
        "count": nodes.len(),
        "registry_file": registry_path().display().to_string(),
        "nodes": nodes,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    #[test]
    fn register_and_heartbeat_roundtrip() {
        let tmp = std::env::temp_dir().join(format!("clrty_node_reg_{}", now_secs()));
        env::set_var("CLRTY_ROOT", tmp.to_str().unwrap());
        let rec = register_node("test-node-1", "node_free", None, 60).unwrap();
        assert_eq!(rec.node_id, "test-node-1");
        let hb = record_heartbeat("test-node-1", Some("1.0.0".into()), Some(100)).unwrap();
        assert!(hb.last_heartbeat_at.is_some());
        let _ = std::fs::remove_dir_all(&tmp);
    }
}
