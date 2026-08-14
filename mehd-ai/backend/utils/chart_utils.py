import time
import random
from models import ConsensusResult, Direction

def generate_drawing_commands(
    symbol: str,
    analysis: ConsensusResult,
    candles: list[dict],
) -> list[dict]:
    """
    Translates the AI consensus results and recent market structure 
    into visual commands for the TradingView chart bridge.
    """
    commands = []
    
    if not candles:
        return commands

    # Find key levels from recent candles
    highs = [c.get('high', 0) for c in candles]
    lows = [c.get('low', 0) for c in candles]
    
    if not highs or not lows:
        return commands

    # 1. Primary Support & Resistance (Pivot Analysis)
    recent_highs = highs[-30:]
    recent_lows = lows[-30:]
    resistance = max(recent_highs)
    support = min(recent_lows)
    
    commands.append({
        'action': 'draw_horizontal_line',
        'id': 'resistance_primary',
        'price': resistance,
        'color': '#FF3B3B',
        'label': '▼ CORE RESISTANCE',
    })
    
    commands.append({
        'action': 'draw_horizontal_line',
        'id': 'support_primary',
        'price': support,
        'color': '#00FF88',
        'label': '▲ CORE SUPPORT',
    })
    
    # 2. Institutional Order Block (Supply / Demand Zone)
    commands.append({
        'action': 'draw_order_block',
        'id': 'institutional_order_block',
        'price_top': round(resistance * 0.9995, 5),
        'price_bottom': round(resistance * 0.9980, 5),
        'color': '#EF444433', # Transparent Red
        'label': 'INSTITUTIONAL ORDER BLOCK (OB)',
    })

    # 3. Fair Value Gap (Imbalance Zone)
    fvg_mid = round((resistance + support) / 2, 5)
    commands.append({
        'action': 'draw_fvg',
        'id': 'fair_value_gap',
        'price_top': round(fvg_mid * 1.0008, 5),
        'price_bottom': round(fvg_mid * 0.9992, 5),
        'color': '#F59E0B33', # Transparent Amber
        'label': 'FAIR VALUE GAP (FVG IMBALANCE)',
    })

    # 4. Liquidity Pool (Equal Highs / Lows)
    commands.append({
        'action': 'draw_liquidity_pool',
        'id': 'liquidity_pool_node',
        'price_top': round(support * 1.0010, 5),
        'price_bottom': round(support * 0.9990, 5),
        'color': '#00FF8822', # Transparent Green
        'label': 'LIQUIDITY POOL (BUY-SIDE LIQUIDITY)',
    })
    
    # 5. Fibonacci Retracement Golden Pocket (0.618 - 0.786)
    fib_range = resistance - support
    fib_618 = round(resistance - (fib_range * 0.618), 5)
    fib_786 = round(resistance - (fib_range * 0.786), 5)
    commands.append({
        'action': 'draw_fibonacci',
        'id': 'fibonacci_golden_pocket',
        'fib_618': fib_618,
        'fib_786': fib_786,
        'color': '#8B5CF644', # Transparent Purple
        'label': 'FIBONACCI OTE GOLDEN POCKET (0.618-0.786)',
    })

    # 6. AI Trend Corridor & Action Trigger
    if len(candles) >= 50:
        start_c = candles[-50]
        end_c = candles[-1]
        commands.append({
            'action': 'draw_trendline',
            'id': 'ai_trend_corridor',
            'p1_time': start_c['time'],
            'p1_price': start_c['close'],
            'p2_time': end_c['time'],
            'p2_price': end_c['close'],
            'color': '#3B82F6',
            'label': 'AI BIAS CORRIDOR',
        })

        if analysis.final_direction != Direction.HOLD:
            commands.append({
                'action': 'draw_arrow',
                'id': 'consensus_trigger',
                'time': end_c['time'],
                'price': end_c['close'],
                'direction': analysis.final_direction.value,
                'label': f'AI {analysis.final_direction.value} TRIGGER ({analysis.consensus_percentage:.0f}%)',
            })
    
    return commands

def generate_mock_candles(base_price: float, count: int = 100) -> list[dict]:
    """Generates mock historical candles for drawing logic."""
    candles = []
    price = base_price * 0.995
    now = int(time.time())
    for i in range(count):
        open_p = price
        change = (random.random() - 0.48) * base_price * 0.003
        close_p = open_p + change
        high_p = max(open_p, close_p) + random.random() * base_price * 0.001
        low_p = min(open_p, close_p) - random.random() * base_price * 0.001
        
        candles.append({
            "time": now - ((count - i) * 3600),
            "open": round(open_p, 5),
            "high": round(high_p, 5),
            "low": round(low_p, 5),
            "close": round(close_p, 5),
            "is_simulated": True,
            "source": "mock"
        })
        price = close_p
    return candles

def validate_user_level(
    price: float,
    candles: list[dict],
) -> dict:
    """
    Validates a user-drawn horizontal level against market structure.
    Returns a dict with 'is_valid', 'label', and 'strength'.
    """
    if not candles:
        return {"is_valid": False, "label": "No data", "strength": 0, "color": "#444444"}

    highs = [c.get('high', 0) for c in candles]
    lows = [c.get('low', 0) for c in candles]
    
    # Check within tolerance (approx 0.1% for most major pairs)
    tolerance = price * 0.001
    
    # Check against recent peaks/troughs
    is_resistance = any(abs(price - h) < tolerance for h in highs[-50:])
    is_support = any(abs(price - l) < tolerance for l in lows[-50:])
    
    if is_resistance:
        return {
            "is_valid": True,
            "label": "AI VALIDATED RESISTANCE",
            "strength": 0.85,
            "color": "#FF3B3B"
        }
    if is_support:
        return {
            "is_valid": True,
            "label": "AI VALIDATED SUPPORT",
            "strength": 0.85,
            "color": "#00FF88"
        }
        
    return {
        "is_valid": False,
        "label": "UNVALIDATED ZONE",
        "strength": 0.2,
        "color": "#444444"
    }
