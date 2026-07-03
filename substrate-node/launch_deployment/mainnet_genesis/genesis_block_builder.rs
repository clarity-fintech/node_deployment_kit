use crate::boot;

pub fn build_genesis_block() -> Result<String, boot::GenesisError> {
    let g = boot::load_and_verify_genesis()?;
    Ok(format!(
        "genesis:{}:{}:{}",
        g.chain_id, g.convergence_id, g.total_supply
    ))
}
