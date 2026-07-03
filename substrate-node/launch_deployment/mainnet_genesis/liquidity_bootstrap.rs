//! Mainnet liquidity bootstrap (Phase 6)

use crate::liquidity_stabilizer::LiquidityStabilizer;

#[derive(Debug, Clone)]
pub struct LiquidityBootstrap {
    pub clrt_amount: u64,
    pub usdc_amount: u64,
    pub eth_amount: u64,
    pub lp_tokens_burned: bool,
}

impl LiquidityBootstrap {
    pub fn from_genesis_bucket(liquidity_clrt: u64) -> Self {
        Self {
            clrt_amount: liquidity_clrt / 2,
            usdc_amount: liquidity_clrt / 4,
            eth_amount: liquidity_clrt / 4,
            lp_tokens_burned: false,
        }
    }

    pub fn seed_pools(&self) -> LiquidityStabilizer {
        LiquidityStabilizer::seed_liquidity(self.clrt_amount, self.usdc_amount)
    }

    pub fn burn_lp_tokens(&mut self) {
        self.lp_tokens_burned = true;
    }
}
