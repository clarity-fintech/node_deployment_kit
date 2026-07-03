# Custom Node Onboarding (L06)

Register a **dev node identity** for the Node Governance layer (L06). This is identity + heartbeat + entitlement — not full validator consensus onboarding (Phase 4+).

## Quick start

### API (free tier)

```bash
curl -X POST https://api.clarity-fintech.com/v1/monetization/node/register \
  -H 'Content-Type: application/json' \
  -d '{"node_id":"partner-node-1","tier":"node_free"}'
```

Response includes `persisted: true` when written to `var/monetization/node_registry.json`.

### Heartbeat

Send every 60s (free) or 15s (sovereign):

```bash
curl -X POST https://api.clarity-fintech.com/v1/monetization/node/heartbeat \
  -H 'Content-Type: application/json' \
  -d '{"node_id":"partner-node-1","version":"1.0.0","uptime_secs":3600}'
```

### CLI

```bash
export CLRTY_API_BASE=https://api.clarity-fintech.com
clrty node register --node-id partner-node-1 --tier node_free --plain
```

Without `CLRTY_API_BASE`, `clrty node register` bootstraps local testnet validators only.

### Clarity Fortress walkthrough

Step 13 at [dev.clrty.io/labs](https://dev.clrty.io/labs) — **Register Node** button calls `POST /v1/monetization/node/register`.

## Sovereign tier (paid)

1. Checkout at `/labs/checkout/` → `node_sovereign` Stripe Payment Link
2. Webhook syncs entitlements to `var/monetization/entitlements.json`
3. Register with customer ID:

```bash
curl -X POST https://api.clarity-fintech.com/v1/monetization/node/register \
  -H 'Content-Type: application/json' \
  -d '{"node_id":"sovereign-1","tier":"node_sovereign","customer_id":"cus_XXXX"}'
```

## API routes

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/v1/monetization/node/register` | Register node (persists registry) |
| POST | `/v1/monetization/node/heartbeat` | Update liveness |
| GET | `/v1/monetization/node/registry` | List registered nodes |
| GET | `/v1/monetization/portal` | Stripe + layer manifest |
| GET | `/v1/monetization/entitlements/:customer_id` | Post-checkout entitlements |

## Verification

```bash
bash scripts/labs/verify_node_onboarding.sh
bash scripts/labs/verify_labs_smoke.sh
```

## What is NOT included yet

- Validator mesh join / consensus participation
- X.509 certificate issuance for consortium validators
- Automatic node suspension on version drift

See [API_FIRST_B2B_INFRASTRUCTURE.md](../monetization/API_FIRST_B2B_INFRASTRUCTURE.md) and [third_party_onboarding.md](../integration/third_party_onboarding.md) for institutional B2B pipeline (KYC, custody, Calendly scheduling).

## B2B scheduling

Partner calls for institutional onboarding: set `CALENDLY_EMBED_URL` and use the embed on the [checkout page](../../monetization-layers/checkout/index.html).
