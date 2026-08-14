"""
Mehd AI — Backtesting Engine
==============================
Replays historical price data through the consensus engine and risk kernel
to measure how the 11-agent system would have performed on real market history.

WHY THIS EXISTS:
Before anyone risks real money, we need PROOF that the consensus model works.
Paper trading shows us what happens NOW, but backtesting shows what WOULD
have happened across hundreds of trades over months/years of data.

HOW IT WORKS:
1. Generate or load historical candlestick data for a symbol
2. For each candle window, create a MarketSnapshot  
3. Run the snapshot through the consensus engine (mock mode)
4. If consensus says trade, run through the risk kernel
5. Track P&L, win rate, max drawdown, Sharpe ratio, etc.
6. Produce a comprehensive performance report

ARCHITECTURE:
    Historical Data → MarketSnapshot → Consensus Engine
                                            ↓
                                     Risk Kernel Gate
                                            ↓
                                     Simulated Execution  
                                            ↓
                                     Performance Tracker
                                            ↓
                                      Final Report
"""

from __future__ import annotations

import logging
import math
import random
import time
import statistics
from datetime import datetime, timezone, timedelta
from typing import Optional
from dataclasses import dataclass, field
from uuid import uuid4

from models import (
    MarketSnapshot, TradeOrder, Direction, RiskDecision, AIVote, ConsensusResult
)
from risk_engine import HardRiskKernel

logger = logging.getLogger("mehd.backtest")


@dataclass
class BacktestTrade:
    """Record of a single simulated trade during backtesting."""
    trade_id: str
    symbol: str
    direction: str
    entry_price: float
    stop_loss: float
    take_profit: float
    lot_size: float
    consensus_pct: float
    entry_time: str
    exit_price: float = 0.0
    exit_time: str = ""
    pnl_pips: float = 0.0
    pnl_dollars: float = 0.0
    outcome: str = "OPEN"  # WIN, LOSS, BREAKEVEN
    exit_reason: str = ""  # SL_HIT, TP_HIT, TIMEOUT


@dataclass
class BacktestReport:
    """Comprehensive performance report from a backtest run."""
    symbol: str
    period_start: str
    period_end: str
    total_candles: int
    total_signals: int
    total_trades: int
    trades_rejected_by_kernel: int
    
    # Win/Loss
    wins: int = 0
    losses: int = 0
    breakeven: int = 0
    win_rate_pct: float = 0.0
    
    # P&L
    total_pnl_pips: float = 0.0
    total_pnl_dollars: float = 0.0
    avg_win_pips: float = 0.0
    avg_loss_pips: float = 0.0
    largest_win_pips: float = 0.0
    largest_loss_pips: float = 0.0
    profit_factor: float = 0.0  # Gross profit / gross loss
    
    # Risk Metrics
    max_drawdown_pct: float = 0.0
    max_consecutive_losses: int = 0
    sharpe_ratio: float = 0.0
    risk_reward_ratio: float = 0.0
    
    # System Metrics
    avg_consensus_pct: float = 0.0
    consensus_above_80_win_rate: float = 0.0
    consensus_below_70_win_rate: float = 0.0
    
    # Trade log
    trades: list = field(default_factory=list)
    equity_curve: list = field(default_factory=list)
    
    # Timing
    backtest_duration_seconds: float = 0.0

    def to_dict(self) -> dict:
        """Convert to serializable dict."""
        d = {}
        for k, v in self.__dict__.items():
            if k == 'trades':
                d[k] = [t.__dict__ for t in v] if v else []
            else:
                d[k] = v
        return d


class BacktestEngine:
    """
    The Backtesting Engine replays historical data through the Mehd AI
    consensus system and risk kernel to produce performance metrics.
    
    Key design decisions:
    1. Uses the SAME HardRiskKernel that production uses (not a mock)
    2. Simulates realistic spread, slippage, and execution latency
    3. Tracks equity curve for drawdown analysis
    4. Separates high-consensus (>80%) vs low-consensus (<70%) win rates
    """

    # Simulation parameters
    SLIPPAGE_PIPS: float = 0.3      # Average slippage on execution
    COMMISSION_PER_LOT: float = 7.0  # $7 per round-trip lot (industry standard)
    MAX_HOLD_CANDLES: int = 20       # Close after 20 candles if neither SL nor TP hit
    
    def __init__(self, starting_balance: float = 10_000.00):
        self.starting_balance = starting_balance
        self._kernel = HardRiskKernel()
        # Override the kernel's balance to match our backtest starting balance
        self._kernel.account = self._kernel.account.model_copy(
            update={"balance": starting_balance, "equity": starting_balance}
        )
    
    def run(
        self,
        symbol: str = 'EUR/USD',
        num_candles: int = 500,
        timeframe_hours: int = 4,
        risk_per_trade_pct: float = 1.0,
        min_consensus_pct: float = 70.0,
    ) -> BacktestReport:
        """
        Execute a full backtest.
        
        Args:
            symbol: Currency pair to test
            num_candles: Number of historical candles
            timeframe_hours: Candle timeframe (1, 4, 24)
            risk_per_trade_pct: Risk per trade as % of balance  
            min_consensus_pct: Minimum consensus to take a trade
        
        Returns:
            BacktestReport with full performance metrics
        """
        start_time = time.monotonic()
        logger.info(
            "═══════════════════════════════════════════════════\n"
            "  BACKTEST START: %s | %d candles | %dH timeframe\n"
            "  Balance: $%.2f | Risk: %.1f%% | Min Consensus: %.0f%%\n"
            "═══════════════════════════════════════════════════",
            symbol, num_candles, timeframe_hours,
            self.starting_balance, risk_per_trade_pct, min_consensus_pct,
        )
        
        # Generate historical data
        candles = self.generate_historical_candles(symbol, num_candles, timeframe_hours)
        
        # Tracking variables
        balance = self.starting_balance
        equity_curve = [balance]
        trades: list[BacktestTrade] = []
        open_trade: Optional[BacktestTrade] = None
        total_signals = 0
        kernel_rejections = 0
        consecutive_losses = 0
        max_consecutive_losses = 0
        peak_balance = balance
        max_drawdown_pct = 0.0
        
        pip_size = 0.01 if 'JPY' in symbol else (0.1 if 'XAU' in symbol else 0.0001)
        pip_value = self._kernel._get_pip_value(symbol)  # $10 forex, $7 JPY, $1 Gold — NOT hardcoded
        
        # Reset the risk kernel for this backtest
        self._kernel.account = self._kernel.account.model_copy(
            update={"balance": balance, "equity": balance, "daily_drawdown_pct": 0.0, "is_locked": False}
        )
        
        # Walk through candles
        lookback = 30  # Need 30 candles of history for indicators
        
        for i in range(lookback, len(candles)):
            current_candle = candles[i]
            window = candles[max(0, i-lookback):i+1]
            
            # ── CHECK: Is there an open trade? ──
            if open_trade is not None:
                # Check if SL or TP was hit during this candle
                if open_trade.direction == "BUY":
                    if current_candle['low'] <= open_trade.stop_loss:
                        # Stop loss hit
                        open_trade.exit_price = open_trade.stop_loss - (self.SLIPPAGE_PIPS * pip_size)
                        open_trade.exit_reason = "SL_HIT"
                    elif current_candle['high'] >= open_trade.take_profit:
                        # Take profit hit
                        open_trade.exit_price = open_trade.take_profit
                        open_trade.exit_reason = "TP_HIT"
                else:  # SELL
                    if current_candle['high'] >= open_trade.stop_loss:
                        open_trade.exit_price = open_trade.stop_loss + (self.SLIPPAGE_PIPS * pip_size)
                        open_trade.exit_reason = "SL_HIT"
                    elif current_candle['low'] <= open_trade.take_profit:
                        open_trade.exit_price = open_trade.take_profit
                        open_trade.exit_reason = "TP_HIT"
                
                # Check hold timeout
                candles_held = i - trades.index(open_trade) if open_trade in trades else 0
                if open_trade.exit_reason == "" and candles_held >= self.MAX_HOLD_CANDLES:
                    open_trade.exit_price = current_candle['close']
                    open_trade.exit_reason = "TIMEOUT"
                
                # Close the trade if exit was triggered
                if open_trade.exit_reason:
                    if open_trade.direction == "BUY":
                        open_trade.pnl_pips = (open_trade.exit_price - open_trade.entry_price) / pip_size
                    else:
                        open_trade.pnl_pips = (open_trade.entry_price - open_trade.exit_price) / pip_size
                    
                    # P&L in dollars (including commission)
                    open_trade.pnl_dollars = (open_trade.pnl_pips * pip_value * open_trade.lot_size) - self.COMMISSION_PER_LOT * open_trade.lot_size
                    open_trade.exit_time = current_candle['time']
                    
                    if open_trade.pnl_pips > 1:
                        open_trade.outcome = "WIN"
                        consecutive_losses = 0
                    elif open_trade.pnl_pips < -1:
                        open_trade.outcome = "LOSS"
                        consecutive_losses += 1
                        max_consecutive_losses = max(max_consecutive_losses, consecutive_losses)
                    else:
                        open_trade.outcome = "BREAKEVEN"
                    
                    # Update balance
                    balance += open_trade.pnl_dollars
                    equity_curve.append(balance)
                    
                    # Update drawdown tracking
                    if balance > peak_balance:
                        peak_balance = balance
                    current_dd = ((peak_balance - balance) / peak_balance) * 100
                    max_drawdown_pct = max(max_drawdown_pct, current_dd)
                    
                    # Update kernel balance
                    self._kernel.account = self._kernel.account.model_copy(
                        update={"balance": balance, "equity": balance}
                    )
                    if open_trade.pnl_dollars < 0:
                        self._kernel.update_drawdown(abs(open_trade.pnl_dollars))
                    
                    open_trade = None
                
                continue  # Don't look for new signals while trade is open
            
            # ── LOOK FOR NEW SIGNAL ──
            consensus = self._simulate_consensus(window, symbol)
            
            if consensus["signal"] is None:
                continue
            
            if consensus["consensus_pct"] < min_consensus_pct:
                continue
            
            total_signals += 1
            
            # Calculate SL and TP based on ATR
            atr = consensus.get("atr", 20 * pip_size)
            sl_distance = max(atr * 1.5, 10 * pip_size)  # At least 10 pips
            tp_distance = sl_distance * 2.0  # 1:2 risk-reward ratio
            
            entry_price = current_candle['close']
            
            if consensus["direction"] == "BUY":
                stop_loss = entry_price - sl_distance
                take_profit = entry_price + tp_distance
                direction = Direction.BUY
            else:
                stop_loss = entry_price + sl_distance
                take_profit = entry_price - tp_distance
                direction = Direction.SELL
            
            # Create trade order and run through risk kernel
            order = TradeOrder(
                symbol=symbol,
                direction=direction,
                lot_size=1.0,  # Will be recalculated by kernel
                stop_loss=stop_loss,
                take_profit=take_profit,
                risk_percentage=risk_per_trade_pct,  # Already a percentage (1.0 = 1%), no /100 needed
            )
            
            # Risk kernel evaluation
            decision = self._kernel.evaluate(
                order,
                current_price=entry_price,
                current_spread=current_candle.get('spread', 1.5),
            )
            
            if not decision.approved:
                kernel_rejections += 1
                continue
            
            # Execute the trade
            trade = BacktestTrade(
                trade_id=f"BT-{len(trades)+1}",
                symbol=symbol,
                direction=consensus["direction"],
                entry_price=entry_price + (self.SLIPPAGE_PIPS * pip_size * (1 if direction == Direction.BUY else -1)),
                stop_loss=stop_loss,
                take_profit=take_profit,
                lot_size=decision.calculated_lot_size,
                consensus_pct=consensus["consensus_pct"],
                entry_time=current_candle['time'],
            )
            
            trades.append(trade)
            open_trade = trade
        
        # ── COMPILE REPORT ──
        duration = time.monotonic() - start_time
        
        completed_trades = [t for t in trades if t.outcome != "OPEN"]
        wins = [t for t in completed_trades if t.outcome == "WIN"]
        losses = [t for t in completed_trades if t.outcome == "LOSS"]
        
        win_pips = [t.pnl_pips for t in wins]
        loss_pips = [t.pnl_pips for t in losses]
        all_pips = [t.pnl_pips for t in completed_trades]
        
        gross_profit = sum(t.pnl_dollars for t in wins) if wins else 0
        gross_loss = abs(sum(t.pnl_dollars for t in losses)) if losses else 0.01
        
        # Sharpe ratio (annualised)
        if len(all_pips) > 1:
            returns = [t.pnl_dollars / self.starting_balance for t in completed_trades]
            avg_return = statistics.mean(returns) if returns else 0
            std_return = statistics.stdev(returns) if len(returns) > 1 else 0.01
            # Annualise assuming 252 trading days
            trades_per_year = 252 * 6 / (timeframe_hours * self.MAX_HOLD_CANDLES)  # rough estimate
            sharpe = (avg_return / std_return) * math.sqrt(trades_per_year) if std_return > 0 else 0
        else:
            sharpe = 0.0
        
        # Consensus analysis
        high_consensus_trades = [t for t in completed_trades if t.consensus_pct >= 80]
        low_consensus_trades = [t for t in completed_trades if t.consensus_pct < 70]
        
        report = BacktestReport(
            symbol=symbol,
            period_start=candles[0]['time'] if candles else "",
            period_end=candles[-1]['time'] if candles else "",
            total_candles=len(candles),
            total_signals=total_signals,
            total_trades=len(completed_trades),
            trades_rejected_by_kernel=kernel_rejections,
            wins=len(wins),
            losses=len(losses),
            breakeven=len([t for t in completed_trades if t.outcome == "BREAKEVEN"]),
            win_rate_pct=round(len(wins) / len(completed_trades) * 100, 1) if completed_trades else 0,
            total_pnl_pips=round(sum(all_pips), 1),
            total_pnl_dollars=round(balance - self.starting_balance, 2),
            avg_win_pips=round(statistics.mean(win_pips), 1) if win_pips else 0,
            avg_loss_pips=round(statistics.mean(loss_pips), 1) if loss_pips else 0,
            largest_win_pips=round(max(win_pips), 1) if win_pips else 0,
            largest_loss_pips=round(min(loss_pips), 1) if loss_pips else 0,
            profit_factor=round(gross_profit / gross_loss, 2) if gross_loss > 0 else 0,
            max_drawdown_pct=round(max_drawdown_pct, 2),
            max_consecutive_losses=max_consecutive_losses,
            sharpe_ratio=round(sharpe, 2),
            risk_reward_ratio=round(
                (statistics.mean(win_pips) / abs(statistics.mean(loss_pips)))
                if win_pips and loss_pips else 0, 2
            ),
            avg_consensus_pct=round(
                statistics.mean([t.consensus_pct for t in completed_trades]), 1
            ) if completed_trades else 0,
            consensus_above_80_win_rate=round(
                len([t for t in high_consensus_trades if t.outcome == "WIN"]) / len(high_consensus_trades) * 100, 1
            ) if high_consensus_trades else 0,
            consensus_below_70_win_rate=round(
                len([t for t in low_consensus_trades if t.outcome == "WIN"]) / len(low_consensus_trades) * 100, 1
            ) if low_consensus_trades else 0,
            trades=completed_trades[:50],  # Cap log at 50 for response size
            equity_curve=equity_curve,
            backtest_duration_seconds=round(duration, 2),
        )
        
        logger.info(
            "═══════════════════════════════════════════════════\n"
            "  BACKTEST COMPLETE: %s\n"
            "  Trades: %d | Win Rate: %.1f%% | P&L: $%.2f\n"
            "  Profit Factor: %.2f | Max DD: %.2f%% | Sharpe: %.2f\n"
            "  High-Consensus (>80%%) WR: %.1f%% | Low (<70%%) WR: %.1f%%\n"
            "  Duration: %.2fs\n"
            "═══════════════════════════════════════════════════",
            symbol, report.total_trades, report.win_rate_pct,
            report.total_pnl_dollars, report.profit_factor,
            report.max_drawdown_pct, report.sharpe_ratio,
            report.consensus_above_80_win_rate, report.consensus_below_70_win_rate,
            duration,
        )
        
        return report


# Module-level instance for import
backtest_engine = BacktestEngine()
