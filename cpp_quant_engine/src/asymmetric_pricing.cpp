#include "asymmetric_pricing.hpp"
#include <cmath>
#include <algorithm>
#include <numeric>

namespace mehd::quant {

double AsymmetricPricingEngine::compute_atr(
    const std::vector<PriceCandle>& candles,
    size_t period
) noexcept {
    if (candles.size() < 2) return 0.0;

    std::vector<double> true_ranges;
    true_ranges.reserve(candles.size() - 1);

    for (size_t i = 1; i < candles.size(); ++i) {
        const double high_low = candles[i].high - candles[i].low;
        const double high_prev_close = std::abs(candles[i].high - candles[i - 1].close);
        const double low_prev_close = std::abs(candles[i].low - candles[i - 1].close);
        
        const double tr = std::max({high_low, high_prev_close, low_prev_close});
        true_ranges.push_back(tr);
    }

    const size_t lookback = std::min(period, true_ranges.size());
    const double sum_tr = std::accumulate(true_ranges.end() - lookback, true_ranges.end(), 0.0);
    return sum_tr / static_cast<double>(lookback);
}

AsymmetricPayoffMatrix AsymmetricPricingEngine::evaluate_asymmetry(
    double entry_price,
    double stop_loss_price,
    double take_profit_price,
    double win_rate_estimate
) noexcept {
    AsymmetricPayoffMatrix matrix;
    matrix.stop_loss_price = stop_loss_price;
    matrix.take_profit_price = take_profit_price;

    const double sl_distance = std::abs(entry_price - stop_loss_price);
    const double tp_distance = std::abs(take_profit_price - entry_price);

    if (sl_distance <= 0.000001) {
        matrix.risk_reward_ratio = 0.0;
        matrix.titan_approved = false;
        matrix.expected_ev_usd = -1.0;
        return matrix;
    }

    const double rr = tp_distance / sl_distance;
    matrix.risk_reward_ratio = rr;

    // TITAN LAW: Only setups with R:R >= 2.0 (preferably >= 3.0) are approved
    matrix.titan_approved = (rr >= 2.0);

    // Expected Value (EV) = (WinRate * Reward) - ((1 - WinRate) * Risk)
    const double loss_rate = 1.0 - win_rate_estimate;
    matrix.expected_ev_usd = (win_rate_estimate * rr) - (loss_rate * 1.0);

    return matrix;
}

} // namespace mehd::quant
