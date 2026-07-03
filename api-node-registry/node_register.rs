use crate::error::{CliError, CliReport};
use crate::pipeline::PipelineContext;
use clrty_substrate::launch_deployment::testnet_manifold;

fn api_base() -> Option<String> {
    std::env::var("CLRTY_API_BASE")
        .ok()
        .filter(|s| !s.is_empty())
        .or_else(|| std::env::var("CLRTY_API_URL").ok().filter(|s| !s.is_empty()))
}

fn parse_flag(args: &[&str], flag: &str) -> Option<String> {
    args.windows(2)
        .find(|w| w[0] == flag)
        .map(|w| w[1].to_string())
}

pub fn run(_ctx: &PipelineContext, args: &[&str]) -> Result<CliReport, CliError> {
    if let Some(base) = api_base() {
        let node_id = parse_flag(args, "--node-id")
            .or_else(|| args.first().map(|s| s.to_string()))
            .unwrap_or_else(|| format!("cli-node-{}", std::process::id()));
        let tier = parse_flag(args, "--tier").unwrap_or_else(|| "node_free".into());
        let body = serde_json::json!({
            "node_id": node_id,
            "tier": tier,
            "customer_id": parse_flag(args, "--customer-id"),
        });
        let url = format!("{base}/v1/monetization/node/register");
        let client = reqwest::blocking::Client::builder()
            .timeout(std::time::Duration::from_secs(15))
            .build()
            .map_err(|e| CliError::Validation(e.to_string()))?;
        let resp = client
            .post(&url)
            .json(&body)
            .send()
            .map_err(|e| CliError::Validation(format!("API register failed: {e}")))?;
        let status = resp.status();
        let text = resp
            .text()
            .unwrap_or_default();
        if !status.is_success() {
            return Err(CliError::Validation(format!("register HTTP {status}: {text}")));
        }
        return Ok(CliReport::ok("node.register", text));
    }

    let validators = testnet_manifold::bootstrap_validator_set::bootstrap_validators(
        testnet_manifold::TESTNET_VALIDATORS,
    );
    Ok(CliReport::ok(
        "node.register",
        format!("local_validators={} (set CLRTY_API_BASE to register via API)", validators.len()),
    ))
}
