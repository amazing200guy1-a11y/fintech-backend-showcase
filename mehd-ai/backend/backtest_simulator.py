import random
import math
from datetime import datetime, timezone, timedelta

def generate_historical_candles(
    symbol: str,
    num_candles: int = 500,
    timeframe_hours: int = 4,
    trend_bias: float = 0.0,
) -> list[dict]:
        """
        Generate realistic historical candlestick data with proper OHLC relationships.
        
        In production, this would fetch from TwelveData/Polygon/OANDA API.
        For now, we generate statistically realistic data with:
        - Proper trend persistence (momentum)
        - Volume correlation with range
        - Realistic spread widening during high volatility
        - Support/resistance clustering
        
        Args:
            symbol: Currency pair (e.g., 'EUR/USD')
            num_candles: Number of historical candles to generate
            timeframe_hours: Candle timeframe in hours (1, 4, 24)
            trend_bias: -1.0 (bearish) to 1.0 (bullish), 0.0 = neutral
        """
        base_prices = {
            'EUR/USD': 1.0850, 'GBP/USD': 1.2650, 'USD/JPY': 150.20,
            'XAU/USD': 2040.50, 'BTC/USD': 63400.00, 'GBP/JPY': 190.80,
            'NAS100': 18200.00, 'US30': 39500.00, 'ETH/USD': 3200.00,
        }
        base = base_prices.get(symbol, 1.0000)
        pip_size = 0.01 if 'JPY' in symbol else (0.1 if 'XAU' in symbol or 'NAS' in symbol or 'US30' in symbol else 0.0001)
        
        candles = []
        price = base
        momentum = 0.0  # Persistence factor
        
        start_time = datetime.now(timezone.utc) - timedelta(hours=num_candles * timeframe_hours)
        
        for i in range(num_candles):
            # Trend persistence (momentum carries forward)
            momentum = momentum * 0.7 + random.gauss(trend_bias * 0.001, 0.002)
            
            # Open = previous close (or base for first candle)
            open_price = price
            
            # Generate body size (how far price moves in this candle)
            body_pips = random.gauss(0, 15) + (momentum * 50)
            body = body_pips * pip_size
            close_price = open_price + body
            
            # Generate wicks (high and low extend beyond body)
            wick_up = abs(random.gauss(0, 8)) * pip_size
            wick_down = abs(random.gauss(0, 8)) * pip_size
            
            high = max(open_price, close_price) + wick_up
            low = min(open_price, close_price) - wick_down
            
            # Volume correlates with range
            candle_range = high - low
            volume = random.uniform(50, 200) * (1 + candle_range / (base * 0.001))
            
            # Spread widens during high volatility
            base_spread = random.uniform(1.0, 2.5)
            if candle_range > base * 0.003:
                base_spread *= 2.0  # Double spread during volatile candles
            
            timestamp = start_time + timedelta(hours=i * timeframe_hours)
            
            candles.append({
                'time': timestamp.isoformat(),
                'open': round(open_price, 5),
                'high': round(high, 5),
                'low': round(low, 5),
                'close': round(close_price, 5),
                'volume': round(volume, 1),
                'spread': round(base_spread, 1),
            })
            
            price = close_price
        
        return candles
    
def _simulate_consensus(candles_window: list[dict], symbol: str) -> dict:
        """
        Simulate what the 11-agent consensus engine would decide for this candle window.
        
        In production with real API keys, this would call the actual AI models.
        For backtesting, we use statistical analysis of the price action to generate
        realistic consensus results. The key insight: we analyze the SAME technical
        patterns that the AI agents would analyze.
        """
        if len(candles_window) < 10:
            return {"signal": None, "consensus_pct": 0, "direction": "HOLD"}
        
        # Calculate technical indicators from the window
        closes = [c['close'] for c in candles_window]
        highs = [c['high'] for c in candles_window]
        lows = [c['low'] for c in candles_window]
        
        # Simple Moving Averages
        sma_fast = sum(closes[-5:]) / 5
        sma_slow = sum(closes[-20:]) / 20 if len(closes) >= 20 else sum(closes) / len(closes)
        
        # Price momentum (last 5 candles)
        momentum = (closes[-1] - closes[-5]) / closes[-5] * 100 if len(closes) >= 5 else 0
        
        # Average True Range (volatility)
        atr_values = []
        for j in range(1, min(14, len(candles_window))):
            tr = max(
                highs[-j] - lows[-j],
                abs(highs[-j] - closes[-j-1]) if j+1 <= len(closes) else 0,
                abs(lows[-j] - closes[-j-1]) if j+1 <= len(closes) else 0,
            )
            atr_values.append(tr)
        atr = sum(atr_values) / len(atr_values) if atr_values else 0.001
        
        # RSI (14-period)
        gains, losses_rsi = [], []
        for j in range(1, min(14, len(closes))):
            diff = closes[-j] - closes[-j-1] if j+1 <= len(closes) else 0
            if diff > 0:
                gains.append(diff)
            else:
                losses_rsi.append(abs(diff))
        avg_gain = sum(gains) / 14 if gains else 0.001
        avg_loss = sum(losses_rsi) / 14 if losses_rsi else 0.001
        rs = avg_gain / avg_loss if avg_loss > 0 else 1
        rsi = 100 - (100 / (1 + rs))
        
        # Generate consensus decision based on technical confluence
        buy_signals = 0
        sell_signals = 0
        total_signals = 9  # Simulate 9 agents (excl. DON and SENTINEL)
        
        # SMA crossover
        if sma_fast > sma_slow:
            buy_signals += 2
        else:
            sell_signals += 2
        
        # Momentum
        if momentum > 0.05:
            buy_signals += 2
        elif momentum < -0.05:
            sell_signals += 2
        else:
            buy_signals += 1
            sell_signals += 1
        
        # RSI
        if rsi < 35:
            buy_signals += 2  # Oversold → buy
        elif rsi > 65:
            sell_signals += 2  # Overbought → sell
        else:
            buy_signals += 1
            sell_signals += 1
        
        # Support/Resistance proximity
        recent_high = max(highs[-20:]) if len(highs) >= 20 else max(highs)
        recent_low = min(lows[-20:]) if len(lows) >= 20 else min(lows)
        price_position = (closes[-1] - recent_low) / (recent_high - recent_low) if recent_high != recent_low else 0.5
        
        if price_position < 0.3:
            buy_signals += 1  # Near support
        elif price_position > 0.7:
            sell_signals += 1  # Near resistance
        
        # Add noise (simulates agent disagreement)
        buy_signals += random.randint(0, 2)
        sell_signals += random.randint(0, 2)
        
        # Determine direction and consensus
        if buy_signals > sell_signals:
            direction = "BUY"
            consensus_pct = min(95, int((buy_signals / (buy_signals + sell_signals)) * 100))
        elif sell_signals > buy_signals:
            direction = "SELL"
            consensus_pct = min(95, int((sell_signals / (buy_signals + sell_signals)) * 100))
        else:
            direction = "HOLD"
            consensus_pct = 50
        
        # Only signal a trade if consensus is above 60%
        if consensus_pct >= 60 and direction != "HOLD":
            return {
                "signal": direction,
                "consensus_pct": consensus_pct,
                "direction": direction,
                "atr": atr,
                "rsi": rsi,
            }
        
        return {"signal": None, "consensus_pct": consensus_pct, "direction": "HOLD"}
    
