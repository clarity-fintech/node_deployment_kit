# Downloads — CLRTY-1 Node Deployment Kit

Everything in this repository is packaged for node operators, infrastructure partners, and custom node builders.

## Primary Download

| Kit | File | Contents |
|-----|------|----------|
| Full Node Deployment Kit | [`dist/node-deployment-kit-full.zip`](dist/node-deployment-kit-full.zip) | Node registry API code, substrate node assets, scripts, chain ops docs, launch manifests, onboarding docs, and deployment guides |
| Node API + SDK Downloads | [`dist/node-api-sdk-downloads.zip`](dist/node-api-sdk-downloads.zip) | Node registry APIs, substrate node surfaces, deployment scripts, launch manifests, onboarding docs, and operator runbooks |
| Operator SDK Downloads | [`dist/operator-sdk-downloads.zip`](dist/operator-sdk-downloads.zip) | Developer SDKs and manifests needed by node operators and custom infrastructure partners |
| Mastermind First Access Pack | [`dist/mastermind-first-access-pack.zip`](dist/mastermind-first-access-pack.zip) | First Access terminal vector, proof-of-fidelity, local inference, closed alpha API routes, and hosted manifest |

Checksums: [`dist/SHA256SUMS.txt`](dist/SHA256SUMS.txt)

## Git Clone

```bash
git clone https://github.com/clarity-fintech/node_deployment_kit.git
cd node_deployment_kit
```

## Included Surfaces

- `api-node-registry/` — node registry, monetization, income ledger, and CLI node registration code.
- `substrate-node/` — launch deployment, validator network, RPC API, settlement, and wallet registry assets.
- `scripts/` — onboarding, deployment, launch, predeploy, smoke, and data-center verification scripts.
- `manifests/` — launch tasks, monetization layers, validator node types, readiness, and mainnet gate manifests.
- `docs/` — onboarding, chain ops, production operations, and third-party integration guidance.

## CLI + Node Onboarding

```bash
git clone https://github.com/clarity-fintech/node_deployment_kit.git
cd node_deployment_kit
bash scripts/labs/verify_node_onboarding.sh

git clone https://github.com/clarity-fintech/clarity_prism_cli.git
cd clarity_prism_cli
clrt node register --dry-run
clrt node heartbeat --node-id test --dry-run
clrt pack download mastermind
```

## Verification

Start with [`QUICKSTART.md`](QUICKSTART.md), configure via [`CONFIGURATION.md`](CONFIGURATION.md), and review [`DEPLOYMENT.md`](DEPLOYMENT.md).
