"""
Profit-Target Rotator (B-Book Stealth Shield)

Tracks rolling 7-day profit per linked broker account and calculates stealth radar thresholds
to protect winning trader accounts from broker 'toxic flow' flagging, spread widening, and bans.
"""
from typing import Dict, Any, List
from datetime import datetime, timezone, timedelta
from storage import storage

DEFAULT_WEEKLY_PROFIT_TARGET_USD = 5000.0

class ProfitRotator:
    """Evaluates stealth radar levels and recommended rotation targets."""

    @staticmethod
    async def get_broker_stealth_status(
        uid: str,
        weekly_target_usd: float = DEFAULT_WEEKLY_PROFIT_TARGET_USD
    ) -> Dict[str, Any]:
        """
        Calculates rolling 7-day PnL per linked broker for the specified user.
        """
        now = datetime.now(timezone.utc)
        seven_days_ago = (now - timedelta(days=7)).isoformat()

        # Query executed trades from storage
        all_trades_doc = await storage.get("trade_history", uid) or {}
        trades: List[Dict[str, Any]] = all_trades_doc.get("trades", [])

        broker_stats: Dict[str, float] = {}

        for trade in trades:
            trade_time = trade.get("timestamp") or trade.get("closed_at")
            broker = trade.get("broker") or trade.get("broker_id") or "Primary Broker"
            pnl = float(trade.get("pnl") or trade.get("profit") or 0.0)

            if trade_time and str(trade_time) >= seven_days_ago:
                broker_stats[broker] = broker_stats.get(broker, 0.0) + pnl

        # Default fallback if no specific broker history exists yet
        if not broker_stats:
            broker_stats["Primary Broker"] = 0.0

        broker_reports = []
        should_rotate = False

        for broker, profit in broker_stats.items():
            pct_used = min(1.0, max(0.0, profit / weekly_target_usd)) if weekly_target_usd > 0 else 0.0
            
            if pct_used >= 1.0:
                status = "TARGET_REACHED"
                color = "purple"
                message = "ROTATION RECOMMENDED — Weekly profit target reached. Rotate execution to secondary broker."
                should_rotate = True
            elif pct_used >= 0.8:
                status = "STEALTH_WARNING"
                color = "gold"
                message = "STEALTH WARNING — Approaching weekly radar limit."
            else:
                status = "STEALTH_ACTIVE"
                color = "green"
                message = "STEALTH ACTIVE — PnL within safe stealth limits."

            broker_reports.append({
                "broker": broker,
                "weekly_pnl": round(profit, 2),
                "weekly_target": round(weekly_target_usd, 2),
                "percentage_used": round(pct_used * 100, 1),
                "status": status,
                "color": color,
                "message": message,
            })

        return {
            "uid": uid,
            "weekly_target_usd": weekly_target_usd,
            "rotation_recommended": should_rotate,
            "brokers": broker_reports,
        }
