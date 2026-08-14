from __future__ import annotations

import logging
from datetime import datetime, timezone
from models import TradeOrder, RiskDecision, Direction

logger = logging.getLogger("mehd.risk_engine")


async def evaluate_order_risk(kernel_ref, order: TradeOrder, current_price: float = 0.0, current_spread: float = 0.0, user_id: str | None = None) -> RiskDecision:
    """Run ALL risk checks on a trade order."""
    await kernel_ref.sync_broker_equity()

    logger.info("Kernel beginning evaluation for %s trade...", order.symbol)
    logger.info(
        "Evaluating order: %s %s %.2f lots (entry_price=%.5f)",
        order.direction.value,
        order.symbol,
        order.lot_size,
        current_price,
    )

    from economic_calendar import calendar_gateway
    minutes_to_news = calendar_gateway.get_minutes_to_next_high_impact_news(order.symbol)
    
    news_threshold = 60 if order.is_auto_execution else 30
    
    if minutes_to_news is not None and minutes_to_news <= news_threshold:
        return RiskDecision(
            approved=False,
            calculated_lot_size=0.0,
            stop_loss=order.stop_loss or 0.0001,
            take_profit=order.take_profit,
            rejection_reason=(
                f"REJECTED: {'SUPREME OVERRIDE' if order.is_auto_execution else 'SOVEREIGN LOCK'}. "
                f"High impact news in {minutes_to_news} mins. "
                "Trading is paused to protect capital from extreme volatility spikes."
            ),
            vetoing_agents=["KERNEL", "SENTINEL"]
        )

    if kernel_ref.account.is_locked:
        if kernel_ref.account.lock_expiry and datetime.now(timezone.utc) >= kernel_ref.account.lock_expiry:
            kernel_ref._unlock_account()
        else:
            expiry_str = (
                kernel_ref.account.lock_expiry.isoformat()
                if kernel_ref.account.lock_expiry
                else "unknown"
            )
            return RiskDecision(
                approved=False,
                calculated_lot_size=0.0,
                stop_loss=order.stop_loss or 0.0001,
                take_profit=order.take_profit,
                rejection_reason=(
                    f"Account is locked: {kernel_ref.account.lock_reason}. "
                    f"Unlocks at {expiry_str}"
                ),
                vetoing_agents=["KERNEL"]
            )

    spread_threshold = kernel_ref.SPREAD_VOLATILITY_THRESHOLD * 0.5 if order.is_auto_execution else kernel_ref.SPREAD_VOLATILITY_THRESHOLD
    
    if current_spread > spread_threshold:
        return RiskDecision(
            approved=False,
            calculated_lot_size=0.0,
            stop_loss=order.stop_loss or 0.0001,
            take_profit=order.take_profit,
            rejection_reason=(
                f"REJECTED: Spread is {current_spread:.1f} pips — above the {spread_threshold:.1f} pip safety threshold. "
                "Trading is paused to prevent bad fills."
            ),
            vetoing_agents=["KERNEL", "TITAN"]
        )

    if order.stop_loss is None:
        return RiskDecision(
            approved=False,
            calculated_lot_size=0.0,
            stop_loss=0.0001,
            take_profit=order.take_profit,
            rejection_reason="REJECTED: No stop-loss provided. A stop-loss is mandatory.",
            vetoing_agents=["KERNEL"]
        )

    safe_lot_size = kernel_ref._calculate_safe_lot_size(order, entry_price=current_price)

    if safe_lot_size < 0.01:
        max_allowed_usd = kernel_ref.account.equity * kernel_ref.MAX_RISK_PER_TRADE_PCT
        return RiskDecision(
            approved=False,
            calculated_lot_size=0.0,
            stop_loss=order.stop_loss,
            take_profit=order.take_profit,
            rejection_reason=(
                f"REJECTED: Lot size too small or risk exceeds limit. "
                f"Maximum allowed risk per trade is \${max_allowed_usd:.2f} (1.0% of balance)."
            ),
            vetoing_agents=["KERNEL"]
        )

    if safe_lot_size < order.lot_size:
        logger.info(
            "Kernel DOWNSIZED lot from %.2f to %.2f to respect 1.0%% risk limit",
            order.lot_size,
            safe_lot_size,
        )

    if order.take_profit is not None and current_price > 0:
        entry = current_price
        sl = order.stop_loss
        tp = order.take_profit

        risk_distance = abs(entry - sl)
        reward_distance = abs(tp - entry)

        is_valid_tp = (
            (order.direction == Direction.BUY and tp > entry)
            or (order.direction == Direction.SELL and tp < entry)
        )

        if not is_valid_tp:
            return RiskDecision(
                approved=False,
                calculated_lot_size=0.0,
                stop_loss=order.stop_loss,
                take_profit=order.take_profit,
                rejection_reason=(
                    f"REJECTED: Invalid Take-Profit level. "
                    f"For a {order.direction.value} trade at {entry}, TP must be "
                    f"{'above' if order.direction == Direction.BUY else 'below'} entry."
                ),
                vetoing_agents=["KERNEL"]
            )

        if risk_distance > 0:
            rr_ratio = reward_distance / risk_distance
            if rr_ratio < 1.0:
                logger.warning(
                    "Sub-optimal R:R ratio (%.2f:1). Minimum recommended is 1:1.",
                    rr_ratio,
                )

    olympus_veto = kernel_ref._verify_olympus_agents(order, current_price)
    if olympus_veto:
        agent = olympus_veto.split(" VETO:")[0] if " VETO:" in olympus_veto else "OLYMPUS"
        return RiskDecision(
            approved=False,
            calculated_lot_size=0.0,
            stop_loss=order.stop_loss,
            take_profit=order.take_profit,
            rejection_reason="REJECTED: %s" % olympus_veto,
            vetoing_agents=[agent]
        )

    return RiskDecision(
        approved=True,
        calculated_lot_size=safe_lot_size,
        stop_loss=order.stop_loss,
        take_profit=order.take_profit,
        expected_price=current_price,
        rejection_reason=None,
    )


async def evaluate_master_block_risk(kernel_ref, order: TradeOrder, current_price: float = 0.0, current_spread: float = 0.0) -> RiskDecision:
    """Special evaluation for Master Block orders."""
    logger.info("Kernel beginning MASTER BLOCK evaluation for %s trade...", order.symbol)

    from economic_calendar import calendar_gateway
    minutes_to_news = calendar_gateway.get_minutes_to_next_high_impact_news(order.symbol)
    
    news_threshold = 60
    if minutes_to_news is not None and minutes_to_news <= news_threshold:
        return RiskDecision(
            approved=False, calculated_lot_size=0.0, stop_loss=order.stop_loss or 0.0001, take_profit=order.take_profit,
            rejection_reason=f"REJECTED: SUPREME OVERRIDE. High impact news in {minutes_to_news} mins.",
            vetoing_agents=["KERNEL", "SENTINEL"]
        )

    spread_threshold = kernel_ref.SPREAD_VOLATILITY_THRESHOLD * 0.5
    if current_spread > spread_threshold:
        return RiskDecision(
            approved=False, calculated_lot_size=0.0, stop_loss=order.stop_loss or 0.0001, take_profit=order.take_profit,
            rejection_reason=f"REJECTED: Spread is {current_spread:.1f} pips — above the {spread_threshold:.1f} pip safety threshold.",
            vetoing_agents=["KERNEL", "TITAN"]
        )

    if order.stop_loss is None:
        return RiskDecision(
            approved=False, calculated_lot_size=0.0, stop_loss=0.0001, take_profit=order.take_profit,
            rejection_reason="REJECTED: No stop-loss provided.",
            vetoing_agents=["KERNEL"]
        )

    olympus_veto = kernel_ref._verify_olympus_agents(order, current_price)
    if olympus_veto:
        agent = olympus_veto.split(" VETO:")[0] if " VETO:" in olympus_veto else "OLYMPUS"
        return RiskDecision(
            approved=False, calculated_lot_size=0.0, stop_loss=order.stop_loss, take_profit=order.take_profit,
            rejection_reason="REJECTED: %s" % olympus_veto,
            vetoing_agents=[agent]
        )

    return RiskDecision(
        approved=True,
        calculated_lot_size=order.lot_size,
        stop_loss=order.stop_loss,
        take_profit=order.take_profit,
        expected_price=current_price,
        rejection_reason=None,
    )
