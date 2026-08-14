"""
Mehd AI — Risk Gateway (Independent Safety Layer)
==================================================
This module wraps ALL trade execution through a gateway that adds
multiple layers of validation on top of the HardRiskKernel.

WHAT THIS ACTUALLY PROTECTS AGAINST:
  ✓ Accidental parameter drift during development (e.g. someone
    changes MAX_RISK_PER_TRADE_PCT in a debugging session and forgets
    to revert it — the seal hash detects the mismatch)
  ✓ Lot size calculation bugs (Gate 3 independently re-derives
    the safe lot size and compares it to the kernel's answer)
  ✓ Missing stop-loss or invalid order fields (caught before broker)
  ✓ Single entry point enforcement (only one executor can be registered)

WHAT THIS DOES NOT PROTECT AGAINST (be honest):
  ✗ A sophisticated attacker with code-level access to this process.
    Since the Gateway runs in the same Python process as the Kernel,
    anyone who can monkey-patch MAX_RISK can also monkey-patch
    _verify_seal_integrity() to return True. The seal is a development
    safety net, NOT a production-grade tamper-proof mechanism.
  ✗ For production-grade tamper resistance, the Risk Kernel should run
    as a SEPARATE MICROSERVICE with its own process boundary, so that
    compromising the web server cannot compromise the risk checks.

ARCHITECTURE:
             ┌──────────────┐
             │  main.py     │
             └──────┬───────┘
                    ▼
        ┌───────────────────────┐
        │   RiskGateway         │ ← THIS FILE
        │   (sealed at boot)    │
        │                       │
        │  1. Drift detection   │
        │  2. HardRiskKernel    │
        │  3. Double-validate   │
        │  4. Audit log         │
        │  5. Broker execute    │
        └───────────┬───────────┘
                    ▼
           ┌──────────────┐
           │  Broker API  │
           └──────────────┘
"""

from __future__ import annotations

import hashlib
import logging
import time
from datetime import datetime, timezone
from typing import Optional, Callable
from dataclasses import dataclass

from models import TradeOrder, RiskDecision, Direction, get_pip_size
from risk_engine import HardRiskKernel

logger = logging.getLogger("mehd.risk_gateway")


@dataclass(frozen=True)
class SealedRiskParameters:
    """
    Immutable snapshot of critical risk parameters, taken at boot time.
    frozen=True means these values literally CANNOT be changed after creation.
    
    If the HardRiskKernel's parameters drift from their boot-time values
    (e.g. due to a bug or accidental edit), the gateway detects the
    mismatch and blocks ALL trades as a safety precaution.
    
    NOTE: This is a development safety net, not a cryptographic guarantee.
    See module docstring for full security scope.
    """
    max_risk_per_trade_pct: float
    max_daily_drawdown_pct: float
    lockout_duration_hours: int
    spread_volatility_threshold: float
    pip_value_per_standard_lot: float
    seal_hash: str  # SHA-256 of all params combined — drift detection fingerprint


class RiskGateway:
    """
    The RiskGateway is the ONLY authorized path to trade execution.
    
    It wraps the HardRiskKernel with additional tamper-proof guarantees:
    
    1. SEALED PARAMETERS: At boot, we snapshot all risk constants and hash them.
       Before every trade, we verify the hash hasn't changed. If someone
       monkey-patches MAX_RISK_PER_TRADE_PCT from 1.0 to 50.0, we catch it.
    
    2. DOUBLE VALIDATION: After the kernel approves, we independently verify
       that the approved lot size doesn't exceed 1% risk. Belt AND suspenders.
    
    3. EXECUTE-ONLY GATEWAY: The broker execution function is registered once
       at startup. No other code path can execute trades.
    
    4. AUDIT TRAIL: Every decision is logged with microsecond timestamps,
       the seal hash, and the full decision chain.
    """

    def __init__(self, kernel: HardRiskKernel):
        self._kernel = kernel
        self._execute_fn: Optional[Callable] = None
        self._total_trades_evaluated = 0
        self._total_trades_blocked = 0
        self._boot_time = datetime.now(timezone.utc)
        
        # SEAL the risk parameters at boot time
        self._sealed = self._create_seal(kernel)
        logger.info(
            "🔐 RiskGateway SEALED — Hash: %s | Max Risk: %.1f%% | Max DD: %.1f%% | Boot: %s",
            self._sealed.seal_hash[:16],
            self._sealed.max_risk_per_trade_pct,
            self._sealed.max_daily_drawdown_pct,
            self._boot_time.isoformat(),
        )

    @staticmethod
    def _create_seal(kernel: HardRiskKernel) -> SealedRiskParameters:
        """Snapshot and hash all critical risk parameters."""
        params_string = (
            f"{kernel.MAX_RISK_PER_TRADE_PCT}:"
            f"{kernel.MAX_DAILY_DRAWDOWN_PCT}:"
            f"{kernel.LOCKOUT_DURATION_HOURS}:"
            f"{kernel.SPREAD_VOLATILITY_THRESHOLD}:"
            f"{kernel.PIP_VALUE_PER_STANDARD_LOT}"
        )
        seal_hash = hashlib.sha256(params_string.encode()).hexdigest()
        
        return SealedRiskParameters(
            max_risk_per_trade_pct=kernel.MAX_RISK_PER_TRADE_PCT,
            max_daily_drawdown_pct=kernel.MAX_DAILY_DRAWDOWN_PCT,
            lockout_duration_hours=kernel.LOCKOUT_DURATION_HOURS,
            spread_volatility_threshold=kernel.SPREAD_VOLATILITY_THRESHOLD,
            pip_value_per_standard_lot=kernel.PIP_VALUE_PER_STANDARD_LOT,
            seal_hash=seal_hash,
        )

    def _verify_seal_integrity(self) -> bool:
        """
        Check that the kernel's risk parameters haven't been tampered with
        since boot. Returns True if everything matches, False if tampered.
        """
        current_seal = self._create_seal(self._kernel)
        if current_seal.seal_hash != self._sealed.seal_hash:
            logger.critical(
                "🚨 RISK PARAMETER TAMPERING DETECTED! "
                "Boot hash: %s, Current hash: %s. "
                "Expected: risk=%.1f%%, dd=%.1f%%. "
                "Found: risk=%.1f%%, dd=%.1f%%. "
                "ALL TRADES BLOCKED.",
                self._sealed.seal_hash[:16],
                current_seal.seal_hash[:16],
                self._sealed.max_risk_per_trade_pct,
                self._sealed.max_daily_drawdown_pct,
                current_seal.max_risk_per_trade_pct,
                current_seal.max_daily_drawdown_pct,
            )
            return False
        return True

    def register_executor(self, execute_fn: Callable) -> None:
        """
        Register the broker execution function. Can only be called ONCE.
        After registration, no other execution path exists.
        """
        if self._execute_fn is not None:
            logger.critical("🚨 ATTEMPTED RE-REGISTRATION OF EXECUTOR — BLOCKED. This is a security violation.")
            raise RuntimeError("Executor already registered. Re-registration is not allowed.")
        
        self._execute_fn = execute_fn
        logger.info("✓ Broker executor registered with RiskGateway")

    async def evaluate_and_execute(
        self,
        order: TradeOrder,
        current_price: float,
        current_spread: float,
        consensus_percentage: float = 0.0,
        user_id: str = "unknown",
    ) -> dict:
        """
        The ONLY public method for trade execution. All paths converge here.
        
        Returns a dict with:
          - approved: bool
          - decision: RiskDecision  
          - seal_valid: bool
          - execution_result: dict or None
          - gateway_timestamp: str
          - evaluation_id: str
        """
        eval_start = time.monotonic()
        self._total_trades_evaluated += 1
        eval_id = f"GW-{int(time.time() * 1000)}-{self._total_trades_evaluated}"
        
        result = {
            "approved": False,
            "decision": None,
            "seal_valid": True,
            "execution_result": None,
            "gateway_timestamp": datetime.now(timezone.utc).isoformat(),
            "evaluation_id": eval_id,
            "latency_ms": 0,
        }
        
        # ── GATE 1: Seal integrity check ────────────────
        if not self._verify_seal_integrity():
            self._total_trades_blocked += 1
            result["seal_valid"] = False
            result["decision"] = RiskDecision(
                approved=False,
                calculated_lot_size=0.0,
                stop_loss=order.stop_loss or 0.0,
                take_profit=order.take_profit,
                rejection_reason="GATEWAY_SECURITY_BREACH: Risk parameters have been tampered with. All trading is suspended.",
            )
            logger.critical("[%s] GATE 1 FAILED: Seal integrity breach for user %s", eval_id, user_id)
            return result

        # ── GATE 2: HardRiskKernel evaluation ───────────
        decision = await self._kernel.evaluate(order, current_price, current_spread, user_id=user_id)
        result["decision"] = decision
        
        if not decision.approved:
            self._total_trades_blocked += 1
            result["latency_ms"] = round((time.monotonic() - eval_start) * 1000, 2)
            logger.info("[%s] GATE 2: Kernel REJECTED — %s", eval_id, decision.rejection_reason)
            return result

        # ── GATE 3: Independent double-validation ───────
        # Use the USER's actual risk setting, not the system maximum.
        # This ensures Gate 3 catches kernel bugs for ANY user risk level (e.g. 1%).
        # Cap it at the system max for safety.
        user_risk_pct = min(
            order.risk_percentage or 1.0,
            self._sealed.max_risk_per_trade_pct
        )
        if getattr(order, 'is_auto_execution', False):
            user_risk_pct = min(user_risk_pct, 0.5)  # Autopilot cap matches kernel
        max_risk_dollars = self._kernel.account.balance * (user_risk_pct / 100)
        pip_size = get_pip_size(order.symbol)
        
        if current_price > 0 and order.stop_loss is not None:
            stop_distance_pips = abs(current_price - order.stop_loss) / pip_size
        else:
            stop_distance_pips = 50.0  # Conservative fallback
        
        stop_distance_pips = max(stop_distance_pips, 1.0)
        independent_max_lots = max_risk_dollars / (stop_distance_pips * self._kernel._get_pip_value(order.symbol))
        independent_max_lots = round(independent_max_lots, 2)
        
        if decision.calculated_lot_size > independent_max_lots * 1.01:  # 1% tolerance for rounding
            self._total_trades_blocked += 1
            result["approved"] = False
            result["decision"] = RiskDecision(
                approved=False,
                calculated_lot_size=0.0,
                stop_loss=order.stop_loss,
                take_profit=order.take_profit,
                rejection_reason=(
                    f"GATEWAY_DOUBLE_CHECK_FAILED: Kernel approved {decision.calculated_lot_size:.4f} lots "
                    f"but independent calculation shows max safe is {independent_max_lots:.4f} lots. "
                    f"Possible kernel tampering detected."
                ),
            )
            logger.critical(
                "[%s] GATE 3 FAILED: Lot size mismatch! Kernel: %.4f, Gateway: %.4f",
                eval_id, decision.calculated_lot_size, independent_max_lots,
            )
            return result

        # ── GATE 4: Execute through registered broker ───
        result["approved"] = True
        
        if self._execute_fn is not None:
            try:
                import asyncio
                if asyncio.iscoroutinefunction(self._execute_fn):
                    exec_result = await self._execute_fn(order, decision)
                else:
                    exec_result = self._execute_fn(order, decision)
                result["execution_result"] = exec_result
                logger.info("[%s] GATE 4: Trade EXECUTED via broker — %s %s %.4f lots",
                           eval_id, order.direction.value, order.symbol, decision.calculated_lot_size)
            except Exception as e:
                logger.error("[%s] GATE 4: Broker execution FAILED — %s", eval_id, e)
                result["execution_result"] = {"error": str(e)}
        else:
            logger.info("[%s] GATE 4: Trade APPROVED (no executor registered — paper mode)", eval_id)
            result["execution_result"] = {"mode": "paper", "status": "simulated"}

        result["latency_ms"] = round((time.monotonic() - eval_start) * 1000, 2)
        
        logger.info(
            "[%s] Gateway Summary: user=%s, %s %s %.4f lots, approved=%s, latency=%.1fms, seal=%s",
            eval_id, user_id, order.direction.value, order.symbol,
            decision.calculated_lot_size, result["approved"],
            result["latency_ms"], self._sealed.seal_hash[:8],
        )
        
        return result

    def get_gateway_status(self) -> dict:
        """Returns gateway health and statistics."""
        seal_valid = self._verify_seal_integrity()
        return {
            "status": "SEALED" if seal_valid else "COMPROMISED",
            "seal_hash": self._sealed.seal_hash[:16] + "...",
            "boot_time": self._boot_time.isoformat(),
            "uptime_seconds": (datetime.now(timezone.utc) - self._boot_time).total_seconds(),
            "total_evaluated": self._total_trades_evaluated,
            "total_blocked": self._total_trades_blocked,
            "block_rate": (
                f"{(self._total_trades_blocked / self._total_trades_evaluated * 100):.1f}%"
                if self._total_trades_evaluated > 0 else "N/A"
            ),
            "risk_parameters": {
                "max_risk_per_trade_pct": self._sealed.max_risk_per_trade_pct,
                "max_daily_drawdown_pct": self._sealed.max_daily_drawdown_pct,
                "lockout_duration_hours": self._sealed.lockout_duration_hours,
                "spread_threshold": self._sealed.spread_volatility_threshold,
            },
            "executor_registered": self._execute_fn is not None,
        }
