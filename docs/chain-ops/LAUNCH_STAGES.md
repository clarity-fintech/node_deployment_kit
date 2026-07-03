# CLRTY Launch Stages — Execution Governance

Chronological launch sequence for VIS → MIRRA → CLARITY → HELIX → Commerce/DeSci.

**100-step roadmap:** [`NANO_ORGANIZATION_100.md`](NANO_ORGANIZATION_100.md) · **Nexus command:** `make help`

---

## 4-Phase Institutional Rollout

Maps the 100 Nano-Organization steps to investor-facing lifecycle phases:

| Phase | Steps | Name | Make target |
|-------|-------|------|-------------|
| 1 | 1–20 | Integrity Core | `make verify-stage-1` |
| 2 | 21–40 | Intelligence Injection | `make verify-stage-2` |
| 3 | 41–60 | Execution & Routing | `make verify-stage-3` |
| 4 | 61–100 | Operational Activation | `make verify-stage-4` · `make verify-stage-5` |

**Progress tracker:** `var/launch/readiness.json` · **Stage gates (0–5):** [`gates/STAGE_GATES.json`](../../gates/STAGE_GATES.json)

The 5 **launch stages** below align with CI gates; institutional phases group steps for deployment narrative.

---

## Stage 1 — Foundation (Infrastructure & Integrity)

**Objective:** System control plane + audit-ready environment.

| Workstream | Repo path | Verify |
|------------|-----------|--------|
| Nexus orchestrator | `Makefile`, `manifests/`, `gates/` | `make init-nexus` |
| Audit gates | `scripts/audit/*` | `make audit-verify` |
| Pretest battery | `scripts/test/full_pretest.sh` | `var/pretest/systemic_readiness.json` |
| Fork-swap stress | `scripts/stress/fork_swap_stress.sh` | Open item in launch readiness |
| Substrate core | `CLRTY_SUBSTRATE/` | `bash scripts/audit/l1_substrate_audit.sh` |

**Pass criteria:** Nexus lock report · MSA/sovereign documented · pretest Zone 1 green.

---

## Stage 2 — Intelligence & Modeling (VIS Alpha)

**Objective:** Train/deploy predictive models; Quantum Skills dry-run.

| Workstream | Repo path | Verify |
|------------|-----------|--------|
| Quantum Skills MCA/TSR/AVR/EHL | `clrty-cli-core/src/skills/` | `cargo test -p clrty-cli-core` |
| Nano N01–N20 | `clrty-cli-core/src/nano_skills/` | `clrty nano list` |
| FeedHub / spread | `arbitrage_core/`, `quant_stack/` | `cargo test -p arbitrage_core` |
| SIM100 batch | `scripts/sim/run_100_events.sh` | seed 42 determinism |
| Runtime tables | `var/trading/quant_skills_table.json` | `clrty skill status` |

**Pass criteria:** Skill determinism · SIM100 green · quant_skills_table persisted.

---

## Stage 3 — Genesis Event (Mainnet TGE)

**Objective:** Immutable one-time mint (16M cap, `mint_authority: null`).

| Workstream | Repo path | Verify |
|------------|-----------|--------|
| Genesis seal | `CLRTY_SUBSTRATE/boot/genesis_entropy.json` | `clrty chain genesis-verify` |
| Tokenomics lock | `docs/tokenomics/TOKENOMICS_LOCKED.md` | Board sign-off **External** |
| Contract gates | `scripts/launch/verify_mainnet_contract_gates.sh` | 5/5 pass |
| Liquidity bucket | 4M CLRTY + stables | `mainnet_listing_config.json` |
| Launch readiness | `scripts/launch/launch_readiness.sh` | `launch_ready: true` |

**Pass criteria:** `make gate-check` · genesis-verify · external audit gates (blockers documented).

---

## Stage 4 — Operational Activation (HELIX & PRISM)

**Objective:** Intelligent execution layer live on clrty-1.

| Workstream | Repo path | Verify |
|------------|-----------|--------|
| HELIX engine | `helix_engine/` HELIX-01..10 | `make helix-verify` |
| HELIX wire | `economic_core`, `arbitrage_core`, committer | ATU 2601–2610 |
| PRISM scaffold | Products program pages + API | Partial |
| Sentinels PoI | `programs/sentinels/` (preview) | Validator mapping partial |
| Investor HELIX panel | `frontend/investor/treasury-dashboard.html` | `#helixPanel` gated |

**Plan reference:** [`PLANS_INDEX.md`](PLANS_INDEX.md) → `helix_engine_integration_c47a6022.plan.md`

**Pass criteria:** `helix_components_report.json` · helix_engine tests · shadow state persist.

---

## Stage 5 — Autonomous Scaling (Commerce & DeSci)

**Objective:** Self-optimizing commerce + research marketplace.

| Workstream | Repo path | Verify |
|------------|-----------|--------|
| CortexPay | `cortexpay_engine/` | `clrty cortexpay` |
| NeuroTemplates | `neuro_templates_engine/`, `templates/` | `clrty nt list` |
| Cognitive onboarding | `cognitive_onboarding_manifest.json` | `/v1/onboarding/*` |
| DeSci / Commerce pages | `frontend/products/desci/`, `commerce/` | Preview only — [`DEFERRED_PUBLIC_WEBSITE.md`](../l1_launch/DEFERRED_PUBLIC_WEBSITE.md) |
| NeuroStable NSD | `settlement/neurostable/` | `clrty neurostable status` |
| Fee flywheel | `economic_engine/tokenomics/` | SIM100 + roadmap M13+ |

**Pass criteria:** Portal sync · public website gate flip when ready (`public_website_integration.json`).

---

## Nexus verification runbook

```bash
make init-nexus      # 1. Initialize federated repos / manifest index
make audit-verify    # 2. Cryptographic security audit
make test-system     # 3. System-wide determinism (SIM100 path)
make gate-check      # 4. Final gate-check (TGE readiness)
```
