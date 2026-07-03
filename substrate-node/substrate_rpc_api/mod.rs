use std::collections::HashMap;

/// Set ranking + governance API (Tasks 49/51/53)
#[derive(Clone)]
pub struct SubstrateRpcApi {
    pub base_url: String,
}

impl SubstrateRpcApi {
    pub fn new(base_url: &str) -> Self {
        Self {
            base_url: base_url.to_string(),
        }
    }

    pub fn get_set_status(&self, address: &str) -> HashMap<String, String> {
        let mut m = HashMap::new();
        m.insert("address".into(), address.to_string());
        let tier = address.bytes().fold(99u8, |acc, b| acc.saturating_sub(b % 3));
        m.insert("set".into(), tier.max(1).to_string());
        m.insert("api_base".into(), self.base_url.clone());
        m
    }
}

pub fn supported_methods() -> Vec<&'static str> {
    vec!["get_set_status", "get_supply", "get_bridge_status"]
}
