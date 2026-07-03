//! Investor wallet registration ledger — pre-KYC whitelist queue.

use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use super::attestation_blob::wallet_from_hex;
use super::commit_payment::SettlementContext;
use super::config::SettlementConfig;
use super::error::SettlementError;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WalletLifecycleStatus {
    Registered,
    Attested,
    Allocated,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WalletRegistration {
    pub wallet: String,
    pub status: WalletLifecycleStatus,
    pub registered_at: u64,
    pub portal_url: String,
    pub tx_hash: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WalletStatus {
    pub wallet: String,
    pub lifecycle: WalletLifecycleStatus,
    pub registered_at: Option<u64>,
    pub portal_url: String,
    pub attested: bool,
    pub kyc_tier: Option<u8>,
    pub attestation_expires_at: Option<u64>,
    pub allocated: bool,
    pub allocation_tx_hash: Option<String>,
    pub clrty_nano: Option<u64>,
    /// Off-chain SAFT agreement reference (Task 29).
    pub saft_reference: Option<String>,
    /// e.g. `506b_accredited`, `506c_verified`, `offshore_reg_s`
    pub investor_class: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RegistryRow {
    wallet: String,
    status: WalletLifecycleStatus,
    registered_at: u64,
    tx_hash: Option<String>,
    #[serde(default)]
    saft_reference: Option<String>,
    #[serde(default)]
    investor_class: Option<String>,
}

pub struct WalletRegistry {
    path: PathBuf,
    portal_url: String,
    rows: Vec<RegistryRow>,
}

impl WalletRegistry {
    pub fn open(dir: &Path, config: &SettlementConfig) -> Result<Self, SettlementError> {
        std::fs::create_dir_all(dir)?;
        let path = dir.join("wallet_registry.wrm");
        let mut rows = Vec::new();
        if path.exists() {
            let file = File::open(&path)?;
            for line in BufReader::new(file).lines() {
                let line = line.map_err(|e| SettlementError::Io(e.to_string()))?;
                if line.trim().is_empty() {
                    continue;
                }
                let row: RegistryRow = serde_json::from_str(&line)
                    .map_err(|e| SettlementError::Io(format!("registry parse: {e}")))?;
                rows.push(row);
            }
        }
        Ok(Self {
            path,
            portal_url: config.portal_url.clone(),
            rows,
        })
    }

    pub fn register_wallet(&mut self, wallet_hex: &str) -> Result<WalletRegistration, SettlementError> {
        let wallet_bytes = wallet_from_hex(wallet_hex)?;
        let wallet = hex::encode(wallet_bytes);
        if let Some(existing) = self.rows.iter().find(|r| r.wallet == wallet) {
            return Ok(WalletRegistration {
                wallet: format!("0x{}", wallet),
                status: existing.status,
                registered_at: existing.registered_at,
                portal_url: self.portal_url.clone(),
                tx_hash: existing.tx_hash.clone(),
            });
        }
        let now = unix_now();
        let row = RegistryRow {
            wallet: wallet.clone(),
            status: WalletLifecycleStatus::Registered,
            registered_at: now,
            tx_hash: None,
            saft_reference: None,
            investor_class: None,
        };
        self.append_row(&row)?;
        self.rows.push(row);
        Ok(WalletRegistration {
            wallet: format!("0x{}", wallet),
            status: WalletLifecycleStatus::Registered,
            registered_at: now,
            portal_url: self.portal_url.clone(),
            tx_hash: None,
        })
    }

    pub fn mark_attested(&mut self, wallet: &[u8; 20]) -> Result<(), SettlementError> {
        let key = hex::encode(wallet);
        let row = self
            .rows
            .iter_mut()
            .find(|r| r.wallet == key)
            .ok_or(SettlementError::WalletNotRegistered)?;
        if row.status == WalletLifecycleStatus::Registered {
            row.status = WalletLifecycleStatus::Attested;
            self.rewrite()?;
        }
        Ok(())
    }

    pub fn set_investor_metadata(
        &mut self,
        wallet: &[u8; 20],
        saft_reference: Option<String>,
        investor_class: Option<String>,
    ) -> Result<(), SettlementError> {
        let key = hex::encode(wallet);
        let row = self
            .rows
            .iter_mut()
            .find(|r| r.wallet == key)
            .ok_or(SettlementError::WalletNotRegistered)?;
        row.saft_reference = saft_reference;
        row.investor_class = investor_class;
        self.rewrite()?;
        Ok(())
    }

    pub fn mark_allocated(&mut self, wallet: &[u8; 20], tx_hash: [u8; 32]) -> Result<(), SettlementError> {
        let key = hex::encode(wallet);
        let tx = hex::encode(tx_hash);
        let row = self
            .rows
            .iter_mut()
            .find(|r| r.wallet == key)
            .ok_or(SettlementError::WalletNotRegistered)?;
        row.status = WalletLifecycleStatus::Allocated;
        row.tx_hash = Some(tx);
        self.rewrite()?;
        Ok(())
    }

    pub fn wallet_status(
        &self,
        wallet_hex: &str,
        ctx: &SettlementContext,
    ) -> Result<WalletStatus, SettlementError> {
        let wallet_bytes = wallet_from_hex(wallet_hex)?;
        let wallet_key = hex::encode(wallet_bytes);
        let row = self.rows.iter().find(|r| r.wallet == wallet_key);

        let attestation = ctx.attestations.get_blob_by_wallet(&wallet_bytes).ok();
        let mut lifecycle = row
            .map(|r| r.status)
            .unwrap_or(WalletLifecycleStatus::Registered);
        if attestation.is_some() && lifecycle == WalletLifecycleStatus::Registered {
            lifecycle = WalletLifecycleStatus::Attested;
        }
        if row
            .and_then(|r| r.tx_hash.as_ref())
            .is_some()
            || lifecycle == WalletLifecycleStatus::Allocated
        {
            lifecycle = WalletLifecycleStatus::Allocated;
        }

        let escrow_key = super::attestation_ledger::wallet_hash(&wallet_bytes);
        let escrow_record = ctx.escrow.get(&escrow_key);

        Ok(WalletStatus {
            wallet: format!("0x{}", wallet_key),
            lifecycle,
            registered_at: row.map(|r| r.registered_at),
            portal_url: self.portal_url.clone(),
            attested: attestation.is_some(),
            kyc_tier: attestation.as_ref().map(|b| b.body.kyc_tier),
            attestation_expires_at: attestation.as_ref().map(|b| b.body.expires_at),
            allocated: escrow_record.is_some(),
            allocation_tx_hash: row.and_then(|r| r.tx_hash.clone()),
            clrty_nano: escrow_record.map(|e| e.total_nano),
            saft_reference: row.and_then(|r| r.saft_reference.clone()),
            investor_class: row.and_then(|r| r.investor_class.clone()),
        })
    }

    fn append_row(&self, row: &RegistryRow) -> Result<(), SettlementError> {
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.path)?;
        let line = serde_json::to_string(row).map_err(|e| SettlementError::Io(e.to_string()))?;
        writeln!(file, "{line}").map_err(|e| SettlementError::Io(e.to_string()))?;
        Ok(())
    }

    fn rewrite(&self) -> Result<(), SettlementError> {
        let mut file = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(&self.path)?;
        for row in &self.rows {
            let line = serde_json::to_string(row).map_err(|e| SettlementError::Io(e.to_string()))?;
            writeln!(file, "{line}").map_err(|e| SettlementError::Io(e.to_string()))?;
        }
        Ok(())
    }
}

fn unix_now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::settlement::attestation_blob::{ComplianceSigner, wallet_from_hex};
    use crate::settlement::attestation_ledger::AttestationLedger;
    use crate::settlement::commit_payment::SettlementContext;

    #[test]
    fn register_idempotent() {
        let dir = std::env::temp_dir().join(format!("wreg_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let config = SettlementConfig::default();
        let mut reg = WalletRegistry::open(&dir, &config).unwrap();
        let w = "0x1234567890123456789012345678901234567890";
        let a = reg.register_wallet(w).unwrap();
        let b = reg.register_wallet(w).unwrap();
        assert_eq!(a.wallet, b.wallet);
        assert_eq!(reg.rows.len(), 1);
    }

    #[test]
    fn status_reflects_attestation() {
        let dir = std::env::temp_dir().join(format!("wstat_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let config = SettlementConfig::default();
        let mut reg = WalletRegistry::open(&dir, &config).unwrap();
        let wallet = [7u8; 20];
        reg.register_wallet(&hex::encode(wallet)).unwrap();
        let signer = ComplianceSigner::from_seed([1u8; 32]);
        let mut ledger = AttestationLedger::open(&dir).unwrap();
        let blob = signer.sign_attestation(wallet, [2u8; 32], 2, 3600, 0);
        ledger.link_wallet(&[2u8; 32], &wallet, &blob).unwrap();
        let ctx = SettlementContext::open(&dir, signer.verifying_key()).unwrap();
        let status = reg
            .wallet_status(&hex::encode(wallet), &ctx)
            .unwrap();
        assert!(status.attested);
    }

    #[test]
    fn investor_metadata_roundtrip() {
        let dir = std::env::temp_dir().join(format!("wmeta_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let config = SettlementConfig::default();
        let mut reg = WalletRegistry::open(&dir, &config).unwrap();
        let w = "0x1234567890123456789012345678901234567890";
        reg.register_wallet(w).unwrap();
        let wallet = wallet_from_hex(w).unwrap();
        reg.set_investor_metadata(
            &wallet,
            Some("SAFT-2026-001".into()),
            Some("506b_accredited".into()),
        )
        .unwrap();
        let signer = ComplianceSigner::from_seed([1u8; 32]);
        let ctx = SettlementContext::open(&dir, signer.verifying_key()).unwrap();
        let status = reg.wallet_status(w, &ctx).unwrap();
        assert_eq!(status.saft_reference.as_deref(), Some("SAFT-2026-001"));
        assert_eq!(status.investor_class.as_deref(), Some("506b_accredited"));
    }
}
