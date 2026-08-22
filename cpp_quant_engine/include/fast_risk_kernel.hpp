#pragma once

#include <string>
#include <vector>
#include <cstdint>
#include <optional>

namespace mehd::quant {

enum class OrderDirection : uint8_t {
    BUY = 1,
    SELL = 2,
    HOLD = 3
};

enum class TimeInForce : uint8_t {
    FOK = 1,  // Fill-Or-Kill
    IOC = 2,  // Immediate-Or-Cancel
    GTC = 3   // Good-Til-Cancelled
};

struct RiskEvaluationResult {
    bool allowed{false};
    double lot_size{0.01};
    double max_loss_usd{0.0};
    double expected_slippage_bound{0.0};
    std::string rejection_reason;
    uint64_t execution_latency_ns{0};
};

class FastRiskKernel {
public:
    FastRiskKernel() = default;
    ~FastRiskKernel() = default;

    /// Evaluates a trade candidate in sub-microsecond latency.
    RiskEvaluationResult evaluate_trade(
        double account_balance,
        double risk_pct,
        double entry_price,
        double stop_loss,
        const std::string& symbol,
        double current_spread_pips,
        double accumulated_daily_loss_usd
    ) noexcept;

    /// Normalizes pip sizes across Forex, Precious Metals, Crypto, and Indices.
    static double get_pip_size(const std::string& symbol) noexcept;

    /// Calculates institutional 3-pip latency arbitrage bounds for FOK orders.
    static double calculate_slippage_bound(
        OrderDirection direction,
        double expected_price,
        double pip_size,
        double max_slippage_pips = 3.0
    ) noexcept;

private:
    static constexpr double MAX_DAILY_DRAWDOWN_PCT = 3.0;
    static constexpr double MAX_SPREAD_THRESHOLD_PIPS = 3.5;
};

} // namespace mehd::quant
