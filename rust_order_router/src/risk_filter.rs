pub struct SovereignRiskFilter {
    pub max_daily_drawdown_pct: f64,
    pub max_risk_per_trade_pct: f64,
    pub max_spread_pips: f64,
}

impl Default for SovereignRiskFilter {
    fn default() -> Self {
        Self {
            max_daily_drawdown_pct: 3.0,
            max_risk_per_trade_pct: 1.0,
            max_spread_pips: 3.5,
        }
    }
}

impl SovereignRiskFilter {
    pub fn validate_order(
        &self,
        equity: f64,
        accumulated_daily_loss: f64,
        spread_pips: f64,
    ) -> Result<(), String> {
        let max_allowed_daily_loss = equity * (self.max_daily_drawdown_pct / 100.0);
        if accumulated_daily_loss >= max_allowed_daily_loss {
            return Err("CIRCUIT BREAKER: 3.0% daily drawdown cap reached. Terminal locked.".into());
        }

        if spread_pips > self.max_spread_pips {
            return Err(format!(
                "SPREAD VOLATILITY GATE: Spread {:.1} pips exceeds threshold {:.1} pips",
                spread_pips, self.max_spread_pips
            ));
        }

        Ok(())
    }
}
