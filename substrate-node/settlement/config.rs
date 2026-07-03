//! Settlement configuration — Safe treasury, exchange rate, allocation caps.

use serde::{Deserialize, Serialize};

use super::error::SettlementError;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AcceptedAsset {
    pub symbol: String,
    pub asset_type: String,
    pub decimals: u8,
    pub contract: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SettlementConfig {
    #[serde(default = "default_treasury_name")]
    pub treasury_name: String,
    #[serde(default = "default_portal_url")]
    pub portal_url: String,
    pub safe_address: String,
    pub chain_id: u64,
    #[serde(default = "default_network_name")]
    pub network_name: String,
    /// USD cents per 1 CLRTY (e.g. 100 = $1.00 per token).
    pub usd_cents_per_clrty: u64,
    /// Maximum CLRTY (whole tokens) allocatable from private_seed bucket.
    pub private_seed_cap_tokens: u64,
    #[serde(default = "default_total_supply")]
    pub total_genesis_supply_tokens: u64,
    /// Token decimals (9 for CLRTY).
    pub decimals: u8,
    pub seed_genesis_min_usd_cents: u64,
    pub strategic_min_usd_cents: u64,
    #[serde(default = "default_eth_usd")]
    pub eth_usd_cents: u64,
    #[serde(default = "default_accepted_assets")]
    pub accepted_assets: Vec<AcceptedAsset>,
}

fn default_treasury_name() -> String {
    "Volkov Intelligence Systems (VIS) Gnosis Safe".into()
}
fn default_portal_url() -> String {
    "https://invest.clrty.network".into()
}
fn default_network_name() -> String {
    "Ethereum Mainnet".into()
}
fn default_total_supply() -> u64 {
    16_000_000
}
fn default_eth_usd() -> u64 {
    300_000
}
fn default_accepted_assets() -> Vec<AcceptedAsset> {
    vec![
        AcceptedAsset {
            symbol: "USDC".into(),
            asset_type: "erc20".into(),
            decimals: 6,
            contract: Some("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48".into()),
        },
        AcceptedAsset {
            symbol: "USDT".into(),
            asset_type: "erc20".into(),
            decimals: 6,
            contract: Some("0xdAC17F958D2ee523a2206206994597C13D831ec7".into()),
        },
        AcceptedAsset {
            symbol: "ETH".into(),
            asset_type: "native".into(),
            decimals: 18,
            contract: None,
        },
    ]
}

impl Default for SettlementConfig {
    fn default() -> Self {
        Self {
            treasury_name: default_treasury_name(),
            portal_url: default_portal_url(),
            safe_address: "0x0000000000000000000000000000000000000000".into(),
            chain_id: 1,
            network_name: default_network_name(),
            usd_cents_per_clrty: 100,
            private_seed_cap_tokens: 2_000_000,
            total_genesis_supply_tokens: 16_000_000,
            decimals: 9,
            seed_genesis_min_usd_cents: 10_000_000,
            strategic_min_usd_cents: 50_000_000,
            eth_usd_cents: 300_000,
            accepted_assets: default_accepted_assets(),
        }
    }
}

impl SettlementConfig {
    pub fn load_embedded() -> Self {
        serde_json::from_str(include_str!("../boot/settlement_config.json"))
            .unwrap_or_default()
    }

    pub fn load_path(path: &str) -> Result<Self, SettlementError> {
        let data = std::fs::read_to_string(path)
            .map_err(|e| SettlementError::Config(format!("read {path}: {e}")))?;
        serde_json::from_str(&data).map_err(|e| SettlementError::Config(e.to_string()))
    }

    pub fn cap_nano(&self) -> u64 {
        self.private_seed_cap_tokens
            .saturating_mul(10u64.pow(self.decimals as u32))
    }

    pub fn asset_by_contract(&self, contract: &str) -> Option<&AcceptedAsset> {
        let c = contract.trim().to_lowercase();
        self.accepted_assets.iter().find(|a| {
            a.contract
                .as_ref()
                .map(|x| x.trim().to_lowercase() == c)
                .unwrap_or(false)
        })
    }

    pub fn native_asset(&self) -> Option<&AcceptedAsset> {
        self.accepted_assets
            .iter()
            .find(|a| a.asset_type == "native")
    }
}
