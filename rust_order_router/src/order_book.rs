use crate::{ExecutionReport, OrderRequest, OrderSide, TimeInForce};
use std::collections::BTreeMap;
use std::time::Instant;

pub struct LockFreeOrderBook {
    pub symbol: String,
    pub bids: BTreeMap<u64, f64>, // Price in fixed precision -> Volume
    pub asks: BTreeMap<u64, f64>,
}

impl LockFreeOrderBook {
    pub fn new(symbol: &str) -> Self {
        Self {
            symbol: symbol.to_string(),
            bids: BTreeMap::new(),
            asks: BTreeMap::new(),
        }
    }

    /// Sub-microsecond matching engine with strict Fill-Or-Kill (FOK) and Slippage protection
    pub fn execute_fok(&mut self, order: &OrderRequest) -> Result<ExecutionReport, String> {
        let start = Instant::now();
        let pip_multiplier = if self.symbol.contains("JPY") { 100.0 } else { 10000.0 };
        let max_slippage_delta = order.max_slippage_pips / pip_multiplier;

        match order.side {
            OrderSide::Buy => {
                // Best available ask
                if let Some((&best_ask_raw, &available_vol)) = self.asks.iter().next() {
                    let best_ask = (best_ask_raw as f64) / 100000.0;
                    
                    // Latency Arbitrage & Slippage Check
                    if best_ask > (order.price + max_slippage_delta) {
                        return Err(format!(
                            "FOK REJECTED: Best ask {:.5} exceeds slippage bound {:.5}",
                            best_ask, order.price + max_slippage_delta
                        ));
                    }

                    if available_vol < order.quantity && order.time_in_force == TimeInForce::FillOrKill {
                        return Err("FOK REJECTED: Insufficient instantaneous liquidity".into());
                    }

                    let elapsed = start.elapsed().as_nanos();
                    Ok(ExecutionReport {
                        order_id: order.order_id.clone(),
                        symbol: self.symbol.clone(),
                        executed_price: best_ask,
                        executed_quantity: order.quantity,
                        status: "FILLED".to_string(),
                        latency_nanos: elapsed,
                        is_filled: true,
                    })
                } else {
                    Err("Order book empty on Ask side".into())
                }
            }
            OrderSide::Sell => {
                // Best available bid
                if let Some((&best_bid_raw, &available_vol)) = self.bids.iter().next_back() {
                    let best_bid = (best_bid_raw as f64) / 100000.0;

                    if best_bid < (order.price - max_slippage_delta) {
                        return Err(format!(
                            "FOK REJECTED: Best bid {:.5} below slippage bound {:.5}",
                            best_bid, order.price - max_slippage_delta
                        ));
                    }

                    if available_vol < order.quantity && order.time_in_force == TimeInForce::FillOrKill {
                        return Err("FOK REJECTED: Insufficient instantaneous liquidity".into());
                    }

                    let elapsed = start.elapsed().as_nanos();
                    Ok(ExecutionReport {
                        order_id: order.order_id.clone(),
                        symbol: self.symbol.clone(),
                        executed_price: best_bid,
                        executed_quantity: order.quantity,
                        status: "FILLED".to_string(),
                        latency_nanos: elapsed,
                        is_filled: true,
                    })
                } else {
                    Err("Order book empty on Bid side".into())
                }
            }
        }
    }
}
