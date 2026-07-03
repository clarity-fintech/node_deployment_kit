# CLRTY Monetization Layers

Single source of truth for paid access layers on CLRTY-1: calculus in the monorepo, billing in `monetization-layers/`, entitlements in `var/monetization/entitlements.json`.

**Architecture blueprint:** [`API_FIRST_B2B_INFRASTRUCTURE.md`](./API_FIRST_B2B_INFRASTRUCTURE.md) · Stripe CLI: [`STRIPE_CLI_SETUP.md`](./STRIPE_CLI_SETUP.md)

## Architecture

```
clrty-monetization-calculus/   → deterministic tax, burn, DaaS, royalty math
CLRTY_SUBSTRATE/boot/monetization_layers_manifest.json  → layer catalog (L01–L14)
clrty-api /v1/monetization/*   → quotes, entitlements, Stripe webhook
monetization-layers/           → Stripe checkout, webhooks, provisioning (→ CLRTY_MONETIZATION_LAYERS repo)
```

## Layer catalog

| ID | Layer | Model | Stripe slug | API route |
|----|-------|-------|-------------|-----------|
| L01 | Tax Engine | 4% on-chain split | — (on_chain) | internal calculus + default execution fee |
| L02 | Burn-to-Access | CLRTY burn per tier | — | `POST /v1/monetization/burn-quote` |
| L03 | DaaS-Core | Subscription + overage | `daas_tier1` | `POST /v1/monetization/daas/quote` |
| L04 | Telemetry-X | Usage + value | `telemetry_edge` | `GET /v1/alpha/telemetry` (gated) |
| L05 | Exec-Sniper API | Base + volume fee | `exec_sniper` (hybrid) | `POST /v1/sniper/quote`, `/execute`, `/status` |
| L06 | Node Governance | Free + paid consortium | `node_free`, `node_sovereign` | `POST /v1/monetization/node/register` |
| L07 | SDK Enterprise | License + maintenance | `sdk_enterprise` | entitlement flag |
| L08 | Marketplace Commission | Escrow % | — (on_chain) | `POST /v1/monetization/marketplace/settle` |
| L09 | Model Royalty | Per-call micro-royalty | — (on_chain) | `POST /v1/monetization/royalty/quote`, `POST /v1/alpha/inference/score` |
| L10 | x402 Metered | Per-request micropay | `x402_metered` | `POST /v1/intelligence/x402/quote` |
| L11 | Predictive Intel SaaS | RAG reports | `predictive_intel` | alpha API (gated) |
| L12 | Private RPC | Infra fee | `private_rpc` | HELIX (modeled) |
| L13 | Governance Stake | Stake barrier | — (on_chain) | governance + execution fees |
| L14 | Stripe Fiat Funnel | Checkout → entitlements | all paid | `POST /v1/integrations/stripe/webhook` |

**Private streams (no Stripe):** see [`monetization-layers/products/private_streams.json`](../../monetization-layers/products/private_streams.json). Default-on execution fees logged to `var/monetization/income_ledger.jsonl`; mirrored to settlement for `ClrtFeeRouter` / `ClrtModelRegistry` deploy.

**Free tier:** `node_free` — non-proprietary data, rate-limited lead-gen.

## Pricing (USD)

| Product | Price | `system_id` |
|---------|-------|-------------|
| DaaS-Core Institutional | $15,000/mo | `daas_tier1` |
| Telemetry-X Edge | $25,000/mo | `telemetry_edge` |
| Exec-Sniper API | $5,000/mo + usage | `exec_sniper` |
| Node Sovereign | $100,000/yr | `node_sovereign` |
| SDK Enterprise | $50,000/yr | `sdk_enterprise` |
| Predictive Intelligence | $20,000/mo | `predictive_intel` |
| Node Free (dev) | $0 | `node_free` |

Provision Stripe products: `python monetization-layers/scripts/provision_stripe_products.py --dry-run`

## API routes

| Method | Path | Description |
|--------|------|-------------|
| GET | `/v1/monetization/layers` | Manifest + entitlements path |
| POST | `/v1/monetization/burn-quote` | L02 burn calculus |
| POST | `/v1/monetization/daas/quote` | L03 DaaS quote |
| POST | `/v1/monetization/sniper/quote` | L05 performance fee (legacy calculus) |
| POST | `/v1/sniper/quote` | L05 route quote preview |
| POST | `/v1/sniper/execute` | L05 trade submit (entitlement-gated) |
| GET | `/v1/sniper/status/:trade_id` | L05 trade lifecycle |
| GET | `/v1/monetization/portal` | Pay portal manifest (Stripe links + private streams) |
| GET | `/v1/monetization/income` | Private income ledger summary + recent rows |
| POST | `/v1/monetization/marketplace/settle` | L08 commission |
| POST | `/v1/monetization/royalty/quote` | L09 royalty |
| POST | `/v1/monetization/tax/preview` | L01 distribution preview |
| POST | `/v1/monetization/performance-roi` | ROI snapshot for Data Center |
| POST | `/v1/monetization/node/register` | L06 node tier registration (persists to `var/monetization/node_registry.json`) |
| POST | `/v1/monetization/node/heartbeat` | L06 node liveness (60s free / 15s sovereign) |
| GET | `/v1/monetization/node/registry` | List registered nodes |
| GET | `/v1/monetization/entitlements/:customer_id` | Customer entitlements |
| POST | `/v1/monetization/entitlements/sync` | Idempotent entitlement sync |
| POST | `/v1/integrations/stripe/webhook` | Stripe → entitlements |
| POST | `/v1/listing/metrics` | Signed ingest only (403 if unsigned) |

## Entitlement gating

Set `CLRTY_ENTITLEMENT_STRICT=1` to require paid entitlements:

- `GET /v1/alpha/telemetry` → `telemetry_edge` or `predictive_intel`
- `POST /v1/alpha/inference/score` → `exec_sniper`, `telemetry_edge`, or `predictive_intel`
- `POST /v1/monetization/sniper/quote` → `exec_sniper`
- `POST /v1/sniper/quote` → `exec_sniper`
- `POST /v1/sniper/execute` → `exec_sniper`

Pass customer id via header `X-CLRTY-Customer-Id` (Stripe `cus_*`).

Closed alpha bearer auth (`CLRTY_ALPHA_TOKEN`) still applies to all `/v1/alpha/*` routes.

## Closed-loop ingestion

Unsigned external data is rejected with **403** and audit log:

- `clrty-signal-bridge` — `validate_signed_payload` before trade validation
- `clrty-api` — `POST /v1/listing/metrics` requires `X-CLRTY-Signature` + allowlisted source or public-canonical id
- Cloudflare workers `coingecko-webhook`, `defillama-ingest` — sign with `CLRTY_INGEST_SIGNING_KEY` or fail closed

Allowlist: `CLRTY_SUBSTRATE/boot/ingestion_allowlist.json`

## Data Center bridge

`scripts/metrics/aggregate_data_center.py` embeds `performance_roi` snapshot (provenance: `clrty-monetization-calculus::performance_roi`) into `var/metrics/data_center_snapshot.json`.

## Verification

```bash
cargo test -p clrty-monetization-calculus
cargo build -p clrty-api
python monetization-layers/scripts/provision_stripe_products.py --dry-run
bash scripts/metrics/verify_data_center.sh
make monetization-verify
```

## Key rotation

See [STRIPE_KEY_ROTATION.md](./STRIPE_KEY_ROTATION.md).

## Related repos

- Monorepo calculus: `$CLRTY_PROJECT/clrty-monetization-calculus`
- Billing package: `monetization-layers/` → `github.com/theangelofwill/CLRTY_MONETIZATION_LAYERS`
- Prism sync manifest: `CLRTY_SUBSTRATE/boot/prism_repo_sync_manifest.json`
