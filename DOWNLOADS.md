# Downloads — CLRTY-1 Node Deployment Kit

Everything in this repository is packaged for node operators, infrastructure partners, and custom node builders.

## Primary Download

| Kit | File | Contents |
|-----|------|----------|
| Full Node Deployment Kit | [`dist/node-deployment-kit-full.zip`](dist/node-deployment-kit-full.zip) | Node registry API code, substrate node assets, scripts, chain ops docs, launch manifests, onboarding docs, and deployment guides |

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

## Verification

Start with [`QUICKSTART.md`](QUICKSTART.md), configure via [`CONFIGURATION.md`](CONFIGURATION.md), and review [`DEPLOYMENT.md`](DEPLOYMENT.md).
