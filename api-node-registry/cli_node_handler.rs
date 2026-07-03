use crate::error::{CliError, CliReport};
use crate::node_register;
use crate::pipeline::PipelineContext;
use clrty_substrate::{
    economic_engine::tokenomics::verify_tokenomics_manifest,
    poc_consensus::PocConsensusEngine,
    verify_genesis,
    TOTAL_SUPPLY,
};

pub fn handle(ctx: &PipelineContext, args: &[&str]) -> Result<CliReport, CliError> {
    match args.first().copied().unwrap_or("status") {
        "status" => {
            let engine = PocConsensusEngine::default();
            let (l, h, e, r) = engine.status_tuple();
            Ok(CliReport::ok(
                "node.status",
                format!("lambda={l:.4} H={h:.4} E={e:.4} R={r:.4}"),
            ))
        }
        "genesis-verify" | "genesis" => match verify_genesis() {
            Ok(g) => {
                let checksum = verify_tokenomics_manifest().map_err(CliError::Validation)?;
                Ok(CliReport::ok(
                    "node.genesis",
                    format!(
                        "chain={} supply={} denom={} checksum=0x{}",
                        g.chain_id,
                        g.total_supply,
                        g.denom,
                        hex::encode(checksum)
                    ),
                ))
            }
            Err(e) => Err(CliError::Validation(e.to_string())),
        },
        "register" => node_register::run(ctx, &args[1..]),
        _ => Ok(CliReport::fail("node", format!("unknown subcommand {}", args[0]))),
    }
}

pub fn token_supply_hint() -> u64 {
    TOTAL_SUPPLY
}
