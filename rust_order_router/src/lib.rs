pub mod order_book;
pub mod risk_filter;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum OrderSide {
    Buy,
    Sell,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TimeInForce {
    FillOrKill,       // FOK
    ImmediateOrCancel, // IOC
    GoodTilCancelled,  // GTC
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrderRequest {
    pub order_id: String,
    pub symbol: String,
    pub side: OrderSide,
    pub price: f64,
    pub quantity: f64,
    pub time_in_force: TimeInForce,
    pub stop_loss: Option<f64>,
    pub take_profit: Option<f64>,
    pub max_slippage_pips: f64,
    pub timestamp: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionReport {
    pub order_id: String,
    pub symbol: String,
    pub executed_price: f64,
    pub executed_quantity: f64,
    pub status: String,
    pub latency_nanos: u128,
    pub is_filled: bool,
}
