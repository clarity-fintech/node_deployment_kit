//! Monetization layers API — calculus, entitlements, Stripe webhook.

use crate::income_ledger;
use crate::node_registry;
use axum::{
    body::Bytes,
    extract::Path,
    http::{HeaderMap, StatusCode},
    Json,
};
use clrty_monetization_calculus::{
    burn_quote, calculate_distribution, marketplace_commission, model_reuse_royalty,
    quote_daas, DaasTier, MarketplaceSettleInput, PerformanceRoiInputs, RoyaltyInput,
    compute_performance_roi,
};
use serde::Deserialize;
use serde_json::{json, Value};
use std::path::PathBuf;

const MANIFEST: &str = include_str!("../../CLRTY_SUBSTRATE/boot/monetization_layers_manifest.json");

fn entitlements_path() -> PathBuf {
    std::env::var("CLRTY_ROOT")
        .map(|r| PathBuf::from(r).join("var/monetization/entitlements.json"))
        .unwrap_or_else(|_| PathBuf::from("var/monetization/entitlements.json"))
}

fn load_entitlements() -> Value {
    let p = entitlements_path();
    if let Ok(data) = std::fs::read_to_string(&p) {
        if let Ok(v) = serde_json::from_str(&data) {
            return v;
        }
    }
    json!({ "customers": {}, "processed_events": [] })
}

fn save_entitlements(v: &Value) -> std::io::Result<()> {
    let p = entitlements_path();
    if let Some(parent) = p.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(&p, serde_json::to_string_pretty(v).unwrap_or_default())
}

pub fn has_entitlement(customer_id: &str, system_id: &str) -> bool {
    let ent = load_entitlements();
    ent.get("customers")
        .and_then(|c| c.get(customer_id))
        .and_then(|c| c.get("systems"))
        .and_then(|s| s.as_array())
        .map(|arr| arr.iter().any(|x| x.as_str() == Some(system_id)))
        .unwrap_or(false)
}

pub async fn get_layers() -> Json<Value> {
    let manifest: Value = serde_json::from_str(MANIFEST).unwrap_or(json!({}));
    Json(json!({
        "manifest": manifest,
        "entitlements_file": entitlements_path().display().to_string(),
    }))
}

#[derive(Debug, Deserialize)]
pub struct BurnQuoteRequest {
    pub tier_cost_usd_cents: u64,
    pub price_usd: f64,
}

pub async fn post_burn_quote(Json(body): Json<BurnQuoteRequest>) -> Json<Value> {
    let q = burn_quote(body.tier_cost_usd_cents, body.price_usd);
    let volume = body.tier_cost_usd_cents.saturating_mul(100);
    let tax = calculate_distribution(volume);
    income_ledger::record_execution_fee(
        "POST /v1/monetization/burn-quote",
        "L02",
        volume,
        &tax,
        0,
        None,
        None,
    );
    Json(serde_json::to_value(q).unwrap_or(json!({})))
}

#[derive(Debug, Deserialize)]
pub struct DaasQuoteRequest {
    pub tier: String,
    pub overage_units: Option<u64>,
}

pub async fn get_daas_quote(Json(body): Json<DaasQuoteRequest>) -> Json<Value> {
    let tier = match body.tier.as_str() {
        "telemetry_edge" => DaasTier::Edge,
        "node_sovereign" => DaasTier::Sovereign,
        _ => DaasTier::Institutional,
    };
    let q = quote_daas(tier, body.overage_units.unwrap_or(0));
    Json(serde_json::to_value(q).unwrap_or(json!({})))
}

#[derive(Debug, Deserialize)]
pub struct SniperQuoteRequest {
    pub volume_usd_cents: u64,
    pub performance_fee_bps: Option<u64>,
    pub customer_id: Option<String>,
}

pub async fn post_sniper_quote(
    headers: HeaderMap,
    Json(body): Json<SniperQuoteRequest>,
) -> Result<Json<Value>, StatusCode> {
    let customer_id = body
        .customer_id
        .clone()
        .or_else(|| {
            headers
                .get("X-CLRTY-Customer-Id")
                .and_then(|v| v.to_str().ok())
                .map(str::to_string)
        });
    if std::env::var("CLRTY_ENTITLEMENT_STRICT").unwrap_or_default() == "1" {
        if !has_entitlement(customer_id.as_deref().unwrap_or(""), "exec_sniper") {
            return Err(StatusCode::FORBIDDEN);
        }
    }
    let bps = body.performance_fee_bps.unwrap_or(10).min(50);
    let fee = body.volume_usd_cents.saturating_mul(bps) / 10_000;
    let tax = calculate_distribution(body.volume_usd_cents);
    income_ledger::record_execution_fee(
        "POST /v1/monetization/sniper/quote",
        "L05",
        body.volume_usd_cents,
        &tax,
        fee,
        customer_id,
        None,
    );
    Ok(Json(json!({
        "volume_usd_cents": body.volume_usd_cents,
        "performance_fee_bps": bps,
        "fee_usd_cents": fee,
        "tax_total": tax.tax_total,
        "founder_share": tax.founder,
        "treasury_share": tax.treasury,
        "layer": "L05"
    })))
}

#[derive(Debug, Deserialize)]
pub struct MarketplaceSettleRequest {
    pub transfer_amount: u64,
    pub commission_bps: Option<u64>,
}

pub async fn post_marketplace_settle(Json(body): Json<MarketplaceSettleRequest>) -> Json<Value> {
    let bps = body.commission_bps.unwrap_or(25);
    let commission = marketplace_commission(&MarketplaceSettleInput {
        transfer_amount: body.transfer_amount,
        commission_bps: bps,
    });
    income_ledger::record_marketplace_commission(
        "POST /v1/monetization/marketplace/settle",
        body.transfer_amount,
        commission,
        bps,
    );
    Json(json!({
        "transfer_amount": body.transfer_amount,
        "commission": commission,
        "net": body.transfer_amount.saturating_sub(commission),
        "layer": "L08",
    }))
}

#[derive(Debug, Deserialize)]
pub struct RoyaltyQuoteRequest {
    pub call_count: u64,
    pub collateral_locked: u64,
    pub royalty_bps: Option<u64>,
    pub model_id: Option<String>,
    pub customer_id: Option<String>,
}

pub async fn post_royalty_quote(Json(body): Json<RoyaltyQuoteRequest>) -> Json<Value> {
    let bps = body.royalty_bps.unwrap_or(10);
    let royalty = model_reuse_royalty(&RoyaltyInput {
        call_count: body.call_count,
        collateral_locked: body.collateral_locked,
        royalty_bps: bps,
    });
    let model_id = body
        .model_id
        .unwrap_or_else(|| "clrty-default-model".into());
    income_ledger::record_royalty(
        "POST /v1/monetization/royalty/quote",
        &model_id,
        bps,
        royalty,
        body.customer_id.clone(),
    );
    Json(json!({ "royalty": royalty, "model_id": model_id, "layer": "L09" }))
}

pub async fn get_entitlements(Path(customer_id): Path<String>) -> Json<Value> {
    let ent = load_entitlements();
    let systems = ent
        .get("customers")
        .and_then(|c| c.get(&customer_id))
        .cloned()
        .unwrap_or(json!({ "systems": [], "active": false }));
    Json(systems)
}

#[derive(Debug, Deserialize)]
pub struct EntitlementsSyncRequest {
    pub customer_id: String,
    pub system_id: String,
    pub active: bool,
    pub stripe_event_id: Option<String>,
}

/// Core entitlement sync — used by API handler and Stripe webhook processor.
pub fn sync_entitlement(body: EntitlementsSyncRequest) -> Value {
    let mut ent = load_entitlements();
    if let Some(eid) = &body.stripe_event_id {
        let processed = ent
            .get("processed_events")
            .and_then(|p| p.as_array())
            .cloned()
            .unwrap_or_default();
        if processed.iter().any(|x| x.as_str() == Some(eid.as_str())) {
            return json!({ "ok": true, "duplicate": true });
        }
        let mut proc = processed;
        proc.push(json!(eid));
        ent["processed_events"] = json!(proc);
    }
    let customers = ent
        .get_mut("customers")
        .and_then(|c| c.as_object_mut());
    if let Some(customers) = customers {
        let entry = customers
            .entry(body.customer_id.clone())
            .or_insert(json!({ "systems": [], "active": false }));
        if body.active {
            let mut systems: Vec<String> = entry
                .get("systems")
                .and_then(|s| s.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_str().map(String::from))
                        .collect()
                })
                .unwrap_or_default();
            if !systems.contains(&body.system_id) {
                systems.push(body.system_id.clone());
            }
            *entry = json!({ "systems": systems, "active": true });
        } else {
            if let Some(systems) = entry.get_mut("systems").and_then(|s| s.as_array_mut()) {
                systems.retain(|s| s.as_str() != Some(body.system_id.as_str()));
            }
            entry["active"] = json!(entry
                .get("systems")
                .and_then(|s| s.as_array())
                .map(|a| !a.is_empty())
                .unwrap_or(false));
        }
    } else {
        ent["customers"] = json!({
            body.customer_id.clone(): { "systems": [body.system_id], "active": body.active }
        });
    }
    let customer_id = body.customer_id;
    let _ = save_entitlements(&ent);
    json!({ "ok": true, "customer_id": customer_id })
}

pub async fn post_entitlements_sync(Json(body): Json<EntitlementsSyncRequest>) -> Json<Value> {
    Json(sync_entitlement(body))
}

pub async fn post_stripe_webhook(headers: HeaderMap, body: Bytes) -> Result<Json<Value>, StatusCode> {
    let secret = std::env::var("STRIPE_WEBHOOK_SECRET")
        .or_else(|_| std::env::var("CLRTY_STRIPE_WEBHOOK_SECRET"))
        .unwrap_or_default();
    if secret.is_empty() {
        // Dev mode: parse without signature verification
        let payload: Value = serde_json::from_slice(&body).map_err(|_| StatusCode::BAD_REQUEST)?;
        return process_stripe_event(payload);
    }
    let sig = headers
        .get("stripe-signature")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    if sig.is_empty() {
        return Err(StatusCode::UNAUTHORIZED);
    }
    // Minimal verification: require header present when secret configured
    let payload: Value = serde_json::from_slice(&body).map_err(|_| StatusCode::BAD_REQUEST)?;
    process_stripe_event(payload)
}

fn process_stripe_event(payload: Value) -> Result<Json<Value>, StatusCode> {
    let event_type = payload.get("type").and_then(|t| t.as_str()).unwrap_or("");
    let event_id = payload
        .get("id")
        .and_then(|t| t.as_str())
        .unwrap_or("")
        .to_string();
    let obj = payload.get("data").and_then(|d| d.get("object"));

    match event_type {
        "checkout.session.completed" | "invoice.paid" => {
            if let Some(session) = obj {
                let customer_id = session
                    .get("customer")
                    .and_then(|c| c.as_str())
                    .unwrap_or("unknown")
                    .to_string();
                let system_id = session
                    .get("metadata")
                    .and_then(|m| m.get("system_id"))
                    .and_then(|s| s.as_str())
                    .unwrap_or("daas_tier1")
                    .to_string();
                sync_entitlement(EntitlementsSyncRequest {
                    customer_id,
                    system_id,
                    active: true,
                    stripe_event_id: Some(event_id),
                });
            }
        }
        "invoice.payment_failed" | "customer.subscription.deleted" => {
            if let Some(session) = obj {
                let customer_id = session
                    .get("customer")
                    .and_then(|c| c.as_str())
                    .unwrap_or("unknown")
                    .to_string();
                let system_id = session
                    .get("metadata")
                    .and_then(|m| m.get("system_id"))
                    .and_then(|s| s.as_str())
                    .unwrap_or("daas_tier1")
                    .to_string();
                sync_entitlement(EntitlementsSyncRequest {
                    customer_id,
                    system_id,
                    active: false,
                    stripe_event_id: Some(event_id),
                });
            }
        }
        _ => {}
    }
    Ok(Json(json!({ "ok": true, "type": event_type })))
}

pub async fn post_tax_preview(Json(body): Json<Value>) -> Json<Value> {
    let volume = body.get("volume").and_then(|v| v.as_u64()).unwrap_or(0);
    let dist = calculate_distribution(volume);
    Json(serde_json::to_value(dist).unwrap_or(json!({})))
}

pub async fn post_performance_roi(Json(body): Json<PerformanceRoiInputs>) -> Json<Value> {
    let snap = compute_performance_roi(&body);
    Json(serde_json::to_value(snap).unwrap_or(json!({})))
}

#[derive(Debug, Deserialize)]
pub struct NodeRegisterRequest {
    pub node_id: String,
    pub tier: String,
    pub customer_id: Option<String>,
}

pub async fn post_node_register(Json(body): Json<NodeRegisterRequest>) -> Json<Value> {
    let paid = body
        .customer_id
        .as_ref()
        .map(|c| has_entitlement(c, "node_sovereign") || has_entitlement(c, "node_free"))
        .unwrap_or(body.tier == "node_free");
    let interval = if body.tier == "node_free" { 60 } else { 15 };
    let persisted = if paid {
        node_registry::register_node(
            &body.node_id,
            &body.tier,
            body.customer_id.clone(),
            interval,
        )
        .ok()
    } else {
        None
    };
    Json(json!({
        "node_id": body.node_id,
        "tier": body.tier,
        "registered": paid,
        "persisted": persisted.is_some(),
        "heartbeat_interval_secs": interval,
        "registry_file": node_registry::registry_summary().get("registry_file"),
    }))
}

#[derive(Debug, Deserialize)]
pub struct NodeHeartbeatRequest {
    pub node_id: String,
    pub version: Option<String>,
    pub uptime_secs: Option<u64>,
}

pub async fn post_node_heartbeat(Json(body): Json<NodeHeartbeatRequest>) -> Result<Json<Value>, StatusCode> {
    match node_registry::record_heartbeat(&body.node_id, body.version.clone(), body.uptime_secs) {
        Ok(rec) => Ok(Json(json!({
            "ok": true,
            "node_id": rec.node_id,
            "last_heartbeat_at": rec.last_heartbeat_at,
        }))),
        Err(_e) => Err(StatusCode::NOT_FOUND),
    }
}

pub async fn get_node_registry() -> Json<Value> {
    Json(node_registry::registry_summary())
}

fn catalog_path() -> PathBuf {
    std::env::var("CLRTY_ROOT")
        .map(|r| PathBuf::from(r).join("monetization-layers/products/catalog.json"))
        .unwrap_or_else(|_| PathBuf::from("monetization-layers/products/catalog.json"))
}

fn portal_manifest_path() -> PathBuf {
    std::env::var("CLRTY_ROOT")
        .map(|r| PathBuf::from(r).join("monetization-layers/products/stripe_portal.json"))
        .unwrap_or_else(|_| PathBuf::from("monetization-layers/products/stripe_portal.json"))
}

fn load_json_file(path: &PathBuf) -> Value {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or(json!({}))
}

/// Full pay portal manifest — catalog + Stripe Payment Links + API route map.
pub async fn get_portal() -> Json<Value> {
    let catalog = load_json_file(&catalog_path());
    let portal = load_json_file(&portal_manifest_path());
    let manifest: Value = serde_json::from_str(MANIFEST).unwrap_or(json!({}));
    let api_base = portal
        .get("api_base")
        .and_then(|v| v.as_str())
        .unwrap_or("https://api.clarity-fintech.com");

    Json(json!({
        "updated": portal.get("updated").cloned().unwrap_or(json!(null)),
        "api_base": api_base,
        "catalog": catalog,
        "products": portal.get("products").cloned().unwrap_or(json!([])),
        "private_streams": load_json_file(&private_streams_path()),
        "manifest_layers": manifest.get("layers").cloned().unwrap_or(json!([])),
        "webhook": "POST /v1/integrations/stripe/webhook",
        "income": "GET /v1/monetization/income",
    }))
}

fn private_streams_path() -> PathBuf {
    std::env::var("CLRTY_ROOT")
        .map(|r| PathBuf::from(r).join("monetization-layers/products/private_streams.json"))
        .unwrap_or_else(|_| PathBuf::from("monetization-layers/products/private_streams.json"))
}
