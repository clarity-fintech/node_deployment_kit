//! Private monetization income ledger — append-only JSONL for on-chain fee streams.

use axum::Json;
use clrty_monetization_calculus::TaxDistribution;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::fs::OpenOptions;
use std::io::Write;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

pub const STREAM_EXECUTION: &str = "execution_governance_fee";
pub const STREAM_ROYALTY: &str = "model_royalty";
pub const STREAM_MARKETPLACE: &str = "marketplace_commission";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IncomeRecord {
    pub ts: String,
    pub stream: String,
    pub layer: String,
    pub route: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub volume_base: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fee_bps: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fee_amount: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub performance_fee: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub founder_usd: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub treasury_usd: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub royalty_bps: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub customer_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tx_ref: Option<String>,
}

pub fn execution_fees_enabled() -> bool {
    std::env::var("CLRTY_EXECUTION_FEE_DEFAULT")
        .map(|v| v != "0" && !v.eq_ignore_ascii_case("false"))
        .unwrap_or(true)
}

pub fn ledger_path() -> PathBuf {
    std::env::var("CLRTY_ROOT")
        .map(|r| PathBuf::from(r).join("var/monetization/income_ledger.jsonl"))
        .unwrap_or_else(|_| PathBuf::from("var/monetization/income_ledger.jsonl"))
}

fn iso_now() -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!("{secs}")
}

fn append_record(record: &IncomeRecord) {
    if !execution_fees_enabled() {
        return;
    }
    let path = ledger_path();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let line = serde_json::to_string(record).unwrap_or_default();
    if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(&path) {
        let _ = writeln!(f, "{line}");
    }
    mirror_settlement(record);
}

fn mirror_settlement(record: &IncomeRecord) {
    let mirror = clrty_substrate::settlement::execution_fee_settle::LedgerEntryMirror {
        ts: record.ts.clone(),
        stream: record.stream.clone(),
        layer: record.layer.clone(),
        route: record.route.clone(),
        volume_base: record.volume_base.unwrap_or(0),
        fee_amount: record.fee_amount.unwrap_or(0),
        customer_id: record.customer_id.clone(),
        model_id: record.model_id.clone(),
    };
    if let Ok(blob) =
        clrty_substrate::settlement::execution_fee_settle::mirror_ledger_entry(&mirror)
    {
        let _ = clrty_substrate::settlement::execution_fee_settle::append_mirror_log(&blob);
    }
}

/// Log execution/governance fee (L01/L05/L13) — default-on.
pub fn record_execution_fee(
    route: &str,
    layer: &str,
    volume_base: u64,
    tax: &TaxDistribution,
    performance_fee: u64,
    customer_id: Option<String>,
    tx_ref: Option<String>,
) {
    let founder = tax.founder as f64;
    let treasury = tax.treasury as f64;
    let record = IncomeRecord {
        ts: iso_now(),
        stream: STREAM_EXECUTION.into(),
        layer: layer.into(),
        route: route.into(),
        volume_base: Some(volume_base),
        fee_bps: Some(400),
        fee_amount: Some(tax.tax_total.saturating_add(performance_fee)),
        performance_fee: Some(performance_fee),
        founder_usd: Some(founder),
        treasury_usd: Some(treasury),
        model_id: None,
        royalty_bps: None,
        customer_id,
        tx_ref,
    };
    append_record(&record);
}

/// Log model royalty (L09).
pub fn record_royalty(
    route: &str,
    model_id: &str,
    royalty_bps: u64,
    fee_amount: u64,
    customer_id: Option<String>,
) {
    let record = IncomeRecord {
        ts: iso_now(),
        stream: STREAM_ROYALTY.into(),
        layer: "L09".into(),
        route: route.into(),
        volume_base: None,
        fee_bps: None,
        fee_amount: Some(fee_amount),
        performance_fee: None,
        founder_usd: None,
        treasury_usd: None,
        model_id: Some(model_id.into()),
        royalty_bps: Some(royalty_bps),
        customer_id,
        tx_ref: None,
    };
    append_record(&record);
}

/// Log marketplace commission (L08).
pub fn record_marketplace_commission(
    route: &str,
    transfer_amount: u64,
    commission: u64,
    commission_bps: u64,
) {
    let record = IncomeRecord {
        ts: iso_now(),
        stream: STREAM_MARKETPLACE.into(),
        layer: "L08".into(),
        route: route.into(),
        volume_base: Some(transfer_amount),
        fee_bps: Some(commission_bps),
        fee_amount: Some(commission),
        performance_fee: None,
        founder_usd: None,
        treasury_usd: None,
        model_id: None,
        royalty_bps: None,
        customer_id: None,
        tx_ref: None,
    };
    append_record(&record);
}

pub fn read_all_records() -> Vec<IncomeRecord> {
    let path = ledger_path();
    let Ok(data) = std::fs::read_to_string(&path) else {
        return vec![];
    };
    data.lines()
        .filter_map(|line| serde_json::from_str::<IncomeRecord>(line.trim()).ok())
        .collect()
}

fn record_ts_secs(ts: &str) -> u64 {
    ts.parse().unwrap_or(0)
}

/// Aggregate income by stream for last 24h and all-time.
pub fn aggregate_totals() -> Value {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let cutoff = now.saturating_sub(86_400);

    let mut streams_24h: HashMap<String, f64> = HashMap::new();
    let mut streams_all: HashMap<String, f64> = HashMap::new();
    let mut governance_24h = 0.0_f64;
    let mut execution_24h = 0.0_f64;
    let mut royalty_24h = 0.0_f64;
    let mut marketplace_24h = 0.0_f64;
    let mut cumulative = 0.0_f64;

    for rec in read_all_records() {
        let amount = rec.fee_amount.unwrap_or(0) as f64;
        cumulative += amount;
        *streams_all.entry(rec.stream.clone()).or_insert(0.0) += amount;

        let ts = record_ts_secs(&rec.ts);
        if ts >= cutoff {
            *streams_24h.entry(rec.stream.clone()).or_insert(0.0) += amount;
            match rec.stream.as_str() {
                STREAM_EXECUTION => {
                    execution_24h += amount;
                    governance_24h += rec.founder_usd.unwrap_or(0.0) + rec.treasury_usd.unwrap_or(0.0);
                }
                STREAM_ROYALTY => royalty_24h += amount,
                STREAM_MARKETPLACE => marketplace_24h += amount,
                _ => {}
            }
        }
    }

    json!({
        "streams_24h": streams_24h,
        "streams_all_time": streams_all,
        "execution_fees_24h_usd": execution_24h,
        "governance_fees_24h_usd": governance_24h,
        "royalty_income_24h_usd": royalty_24h,
        "marketplace_commission_24h_usd": marketplace_24h,
        "private_income_cumulative_usd": cumulative,
        "record_count": read_all_records().len(),
    })
}

pub fn get_income_summary(limit: usize) -> Value {
    let records = read_all_records();
    let start = records.len().saturating_sub(limit);
    let recent: Vec<Value> = records[start..]
        .iter()
        .map(|r| serde_json::to_value(r).unwrap_or(json!({})))
        .collect();
    let mut totals = aggregate_totals();
    if let Some(obj) = totals.as_object_mut() {
        obj.insert("recent".into(), json!(recent));
    }
    totals
}

pub async fn get_income() -> Json<Value> {
    Json(get_income_summary(50))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn execution_fees_default_on() {
        std::env::remove_var("CLRTY_EXECUTION_FEE_DEFAULT");
        assert!(execution_fees_enabled());
    }

    #[test]
    fn aggregate_empty_ledger() {
        let totals = aggregate_totals();
        assert_eq!(totals["execution_fees_24h_usd"], 0.0);
    }
}
