//! Investor-facing genesis participation instructions and allocation preview.

use serde::{Deserialize, Serialize};

use super::allocation_weights::{
    calculate_clrty_allocation, AllocationPhase,
};
use super::config::SettlementConfig;
use super::error::SettlementError;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AllocationPreview {
    pub usd_cents: u64,
    pub usd_display: String,
    pub treasury_address: String,
    pub phase: String,
    pub weight_multiplier: f64,
    pub clrty_tokens: f64,
    pub clrty_nano: u64,
    pub cliff_months: u64,
    pub vest_months: u64,
    pub benefits: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GenesisParticipationInstructions {
    pub protocol_version: String,
    pub portal_url: String,
    pub treasury_name: String,
    pub treasury_address: String,
    pub treasury_verified: bool,
    pub network: String,
    pub chain_id: u64,
    pub accepted_assets: Vec<String>,
    pub total_genesis_supply: u64,
    pub private_seed_cap_tokens: u64,
    pub reference_price_usd: String,
    pub minimum_investment_usd: String,
    pub steps: Vec<InstructionStep>,
    pub allocation_tiers: Vec<AllocationTier>,
    pub benefits_summary: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstructionStep {
    pub step: u8,
    pub title: String,
    pub actions: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AllocationTier {
    pub name: String,
    pub usd_threshold: String,
    pub weight_multiplier: f64,
    pub cliff_months: u64,
    pub vest_months: u64,
    pub benefits: Vec<String>,
}

pub fn phase_label(phase: AllocationPhase) -> &'static str {
    match phase {
        AllocationPhase::SeedGenesis => "Seed Genesis",
        AllocationPhase::StrategicRound => "Strategic Round",
        AllocationPhase::HardwareNodePartner => "Hardware Node Partner",
        AllocationPhase::BelowMinimum => "Below Minimum",
    }
}

pub fn benefits_for_phase(phase: AllocationPhase) -> Vec<String> {
    match phase {
        AllocationPhase::SeedGenesis => vec![
            "1.5x compute-weighted register allocation".into(),
            "6-month hard lock + 24-month linear vesting".into(),
            "Early genesis priority lanes in network manifold".into(),
            "Deterministic scarcity — capped 16M CLRTY substrate".into(),
        ],
        AllocationPhase::StrategicRound => vec![
            "1.75x compute-weighted register allocation".into(),
            "6-month hard lock + 24-month linear vesting".into(),
            "High-priority execution lanes within network manifold".into(),
            "Programmatic Gnosis Safe + vesting escrow protection".into(),
        ],
        AllocationPhase::HardwareNodePartner => vec![
            "2.0x compute-weighted register allocation".into(),
            "12-month hard lock + 36-month linear vesting".into(),
            "Validator onboarding gate priority status".into(),
            "Dedicated L3 cache partition binding".into(),
        ],
        AllocationPhase::BelowMinimum => vec![
            "Minimum $100,000 USD equivalent required for Seed Genesis".into(),
        ],
    }
}

pub fn preview_allocation(
    usd_cents: u64,
    hardware_score: u8,
    config: &SettlementConfig,
    treasury_address: &str,
) -> Result<AllocationPreview, SettlementError> {
    let hardware_attested = hardware_score >= 80;
    let phase = if hardware_attested {
        AllocationPhase::HardwareNodePartner
    } else {
        AllocationPhase::from_usd_cents(usd_cents, config)
    };
    let multiplier = phase.weight_multiplier(hardware_attested);
    let clrty_nano = calculate_clrty_allocation(usd_cents, phase, hardware_score, config)?;
    let clrty_tokens = clrty_nano as f64 / 10f64.powi(config.decimals as i32);
    Ok(AllocationPreview {
        usd_cents,
        usd_display: format_usd(usd_cents),
        treasury_address: treasury_address.to_string(),
        phase: phase_label(phase).into(),
        weight_multiplier: multiplier,
        clrty_tokens,
        clrty_nano,
        cliff_months: phase.cliff_months(),
        vest_months: phase.vest_months(),
        benefits: benefits_for_phase(phase),
    })
}

pub fn genesis_instructions(
    config: &SettlementConfig,
    treasury_address: &str,
    treasury_verified: bool,
) -> GenesisParticipationInstructions {
    GenesisParticipationInstructions {
        protocol_version: "genesis-v1".into(),
        portal_url: config.portal_url.clone(),
        treasury_name: config.treasury_name.clone(),
        treasury_address: treasury_address.to_string(),
        treasury_verified,
        network: config.network_name.clone(),
        chain_id: config.chain_id,
        accepted_assets: config
            .accepted_assets
            .iter()
            .map(|a| a.symbol.clone())
            .collect(),
        total_genesis_supply: config.total_genesis_supply_tokens,
        private_seed_cap_tokens: config.private_seed_cap_tokens,
        reference_price_usd: format_usd(config.usd_cents_per_clrty),
        minimum_investment_usd: format_usd(config.seed_genesis_min_usd_cents),
        steps: vec![
            InstructionStep {
                step: 1,
                title: "Identity & Compliance Verification".into(),
                actions: vec![
                    format!("Register wallet: POST /v1/compliance/wallet/register"),
                    format!("Navigate to {}", config.portal_url),
                    "Complete VIS Compliance Verification (KYC/AML)".into(),
                    "Download your Attestation Blob (VIS Master Key signed, #0A192F salt)".into(),
                ],
            },
            InstructionStep {
                step: 2,
                title: "Capital Settlement (USDC / USDT / ETH)".into(),
                actions: vec![
                    format!("Transfer from your verified wallet to treasury: {}", treasury_address),
                    "Accepted assets: USDC, USDT, or native ETH only (Ethereum Mainnet)".into(),
                    "Ensure sender wallet matches your Attestation Blob wallet address".into(),
                    "After transfer: POST /v1/compliance/deposit/confirm with tx_hash".into(),
                ],
            },
            InstructionStep {
                step: 3,
                title: "Automatic Allocation & Register Binding".into(),
                actions: vec![
                    "VIS gatekeeper detects Safe deposit via Treasury API".into(),
                    "Attestation verified against Master Compliance Key".into(),
                    "CLRTY mapped to dedicated L3 cache register partition".into(),
                    "Tokens locked in ecosystem vesting escrow (6M cliff / 24M linear default)".into(),
                ],
            },
        ],
        allocation_tiers: vec![
            AllocationTier {
                name: "Seed Genesis".into(),
                usd_threshold: "$100,000 – $500,000".into(),
                weight_multiplier: 1.5,
                cliff_months: 6,
                vest_months: 24,
                benefits: benefits_for_phase(AllocationPhase::SeedGenesis),
            },
            AllocationTier {
                name: "Strategic Round".into(),
                usd_threshold: "$500,000+".into(),
                weight_multiplier: 1.75,
                cliff_months: 6,
                vest_months: 24,
                benefits: benefits_for_phase(AllocationPhase::StrategicRound),
            },
            AllocationTier {
                name: "Hardware Node Partner".into(),
                usd_threshold: "Dedicated compute attestation".into(),
                weight_multiplier: 2.0,
                cliff_months: 12,
                vest_months: 36,
                benefits: benefits_for_phase(AllocationPhase::HardwareNodePartner),
            },
        ],
        benefits_summary: vec![
            "Deterministic scarcity — 16,000,000 CLRTY genesis cap".into(),
            "Compute-weighted priority tied to hardware register performance".into(),
            "Programmatic protection via Gnosis Safe multi-sig treasury".into(),
            "Immutable vesting escrow — allocation protected from volatility".into(),
            "Zero third-party crowdfunding middlemen — direct-to-treasury settlement".into(),
        ],
    }
}

fn format_usd(cents: u64) -> String {
    format!("${:.2}", cents as f64 / 100.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strategic_preview_uses_1_75x() {
        let config = SettlementConfig::default();
        let preview = preview_allocation(50_000_000, 0, &config, "0x1234567890123456789012345678901234567890").unwrap();
        assert_eq!(preview.weight_multiplier, 1.75);
        assert_eq!(preview.phase, "Strategic Round");
    }
}
