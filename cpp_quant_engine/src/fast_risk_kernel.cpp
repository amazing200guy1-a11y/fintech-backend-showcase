#include "fast_risk_kernel.hpp"
#include <chrono>
#include <cmath>
#include <algorithm>

namespace mehd::quant {

double FastRiskKernel::get_pip_size(const std::string& symbol) noexcept {
    if (symbol.find("JPY") != std::string::npos) return 0.01;
    if (symbol.find("XAU") != std::string::npos || symbol.find("GOLD") != std::string::npos) return 0.10;
    if (symbol.find("XAG") != std::string::npos || symbol.find("SILVER") != std::string::npos) return 0.01;
    if (symbol.find("BTC") != std::string::npos) return 1.00;
    if (symbol.find("ETH") != std::string::npos) return 0.10;
    if (symbol.find("SPX") != std::string::npos || symbol.find("NAS") != std::string::npos || symbol.find("US30") != std::string::npos) return 1.00;
    return 0.0001; // Standard Forex
}

double FastRiskKernel::calculate_slippage_bound(
    OrderDirection direction,
    double expected_price,
    double pip_size,
    double max_slippage_pips
) noexcept {
    const double delta = max_slippage_pips * pip_size;
    if (direction == OrderDirection::BUY) {
        return expected_price + delta;
    } else {
        return expected_price - delta;
    }
}

RiskEvaluationResult FastRiskKernel::evaluate_trade(
    double account_balance,
    double risk_pct,
    double entry_price,
    double stop_loss,
    const std::string& symbol,
    double current_spread_pips,
    double accumulated_daily_loss_usd
) noexcept {
    const auto start_time = std::chrono::steady_clock::now();
    RiskEvaluationResult result;

    // Gate 1: Account & Risk Parameter Boundary Check
    if (account_balance <= 0.0 || risk_pct <= 0.0 || risk_pct > 10.0) {
        result.allowed = false;
        result.rejection_reason = "Invalid account equity or risk percentage exceeding sovereign bounds (0.1% - 10.0%).";
        return result;
    }

    // Gate 2: Daily Drawdown Circuit Breaker (3.0% Hard Cap)
    const double max_daily_loss_usd = account_balance * (MAX_DAILY_DRAWDOWN_PCT / 100.0);
    if (accumulated_daily_loss_usd >= max_daily_loss_usd) {
        result.allowed = false;
        result.rejection_reason = "Daily Drawdown Circuit Breaker tripped (3.0% max loss). Terminal locked for 24h.";
        return result;
    }

    // Gate 3: Spread Volatility Defense (Prevent execution during rollover widening)
    if (current_spread_pips > MAX_SPREAD_THRESHOLD_PIPS) {
        result.allowed = false;
        result.rejection_reason = "Spread blowout detected (" + std::to_string(current_spread_pips) + " pips). Execution blocked.";
        return result;
    }

    // Gate 4: Mathematical Lot Sizing & Asymmetric Stop Loss Validation
    const double pip_size = get_pip_size(symbol);
    const double sl_distance = std::abs(entry_price - stop_loss);
    const double sl_pips = sl_distance / pip_size;

    if (sl_pips < 2.0) {
        result.allowed = false;
        result.rejection_reason = "Stop loss distance is unviably tight (< 2.0 pips). Prevents spread stop-outs.";
        return result;
    }

    // Single source of truth pip value ($10 for standard forex, $1 for gold, etc.)
    double pip_value_per_lot = 10.0;
    if (symbol.find("XAU") != std::string::npos || symbol.find("GOLD") != std::string::npos) pip_value_per_lot = 1.0;
    else if (symbol.find("JPY") != std::string::npos) pip_value_per_lot = 9.0;
    else if (symbol.find("BTC") != std::string::npos || symbol.find("ETH") != std::string::npos) pip_value_per_lot = 1.0;
    else if (symbol.find("SPX") != std::string::npos || symbol.find("NAS") != std::string::npos) pip_value_per_lot = 1.0;

    const double max_loss_cash = account_balance * (risk_pct / 100.0);
    const double raw_lot = max_loss_cash / (sl_pips * pip_value_per_lot);
    const double clamped_lot = std::clamp(std::floor(raw_lot * 100.0) / 100.0, 0.01, 50.0);

    const auto end_time = std::chrono::steady_clock::now();
    const auto elapsed_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(end_time - start_time).count();

    result.allowed = true;
    result.lot_size = clamped_lot;
    result.max_loss_usd = max_loss_cash;
    result.expected_slippage_bound = calculate_slippage_bound(
        (entry_price > stop_loss ? OrderDirection::BUY : OrderDirection::SELL),
        entry_price,
        pip_size,
        3.0
    );
    result.execution_latency_ns = static_cast<uint64_t>(elapsed_ns);

    return result;
}

} // namespace mehd::quant
