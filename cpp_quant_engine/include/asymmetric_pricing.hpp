#pragma once

#include <vector>
#include <string>
#include <cstdint>

namespace mehd::quant {

struct PriceCandle {
    double open{0.0};
    double high{0.0};
    double low{0.0};
    double close{0.0};
    double volume{0.0};
    uint64_t timestamp{0};
};

struct AsymmetricPayoffMatrix {
    double risk_reward_ratio{0.0};
    double take_profit_price{0.0};
    double stop_loss_price{0.0};
    bool titan_approved{false};
    double expected_ev_usd{0.0};
};

class AsymmetricPricingEngine {
public:
    AsymmetricPricingEngine() = default;

    /// Computes Average True Range (ATR) with SIMD acceleration
    static double compute_atr(const std::vector<PriceCandle>& candles, size_t period = 14) noexcept;

    /// Validates and constructs TITAN asymmetric payout geometries (>= 2:1 or 3:1)
    static AsymmetricPayoffMatrix evaluate_asymmetry(
        double entry_price,
        double stop_loss_price,
        double take_profit_price,
        double win_rate_estimate = 0.70
    ) noexcept;
};

} // namespace mehd::quant
