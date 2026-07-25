"""
Mehd AI — Hardened Multi-Condition Kill Switch Engine
======================================================
This module acts as the ultimate defensive shield for MEHD AI.
It evaluates execution health right before any order is sent to the broker,
enforcing trading halts when safety conditions are violated.

KILL SWITCH CONDITIONS:
  1. 5-Pip Broker Anti-Manipulation Discrepancy Check (Broker Quote vs Independent Oracle)
  2. 30-Second Secretary News Filter Heartbeat Timeout (with 5-minute boot grace period)
  3. Execution Latency Spike (> 100ms)
  4. Operator Manual Panic Button Override
"""

import time
import logging
from typing import Dict, Any

logger = logging.getLogger("mehd.hardened_kill_switch")

# Configuration constants
_MAX_PRICE_DISCREPANCY_PIPS = 5.0      # Pips of discrepancy before broker manipulation alert
_MAX_NEWS_HEARTBEAT_TIMEOUT_SEC = 30.0 # Seconds before news heartbeat timeout triggers HALT
_MAX_LATENCY_MS = 100.0                # Milliseconds before latency spike triggers HALT
_BOOT_GRACE_PERIOD_SEC = 300.0         # 5-minute grace on boot — heartbeat not yet established


class HardenedKillSwitch:
    def __init__(self):
        # Initialize heartbeat to current time so we start in OK state.
        # Boot grace period prevents false HALT before secretary starts ticking.
        self._last_news_heartbeat: float = time.time()
        self._boot_time: float = time.time()
        self._is_panic_activated: bool = False

    def record_news_heartbeat(self):
        """Called whenever the Secretary News Filter processes a cycle."""
        self._last_news_heartbeat = time.time()

    def trigger_panic_button(self, operator_name: str = "OPERATOR") -> Dict[str, Any]:
        """Manual Panic Button Override from UI."""
        self._is_panic_activated = True
        logger.critical("🚨 EMERGENCY PANIC BUTTON TRIGGERED BY %s! FLATTENING ALL POSITIONS!", operator_name)
        return {
            "status": "HALTED",
            "reason": f"MANUAL_PANIC_BUTTON_TRIGGERED_BY_{operator_name}",
            "action": "FLATTEN_ALL_POSITIONS_AND_PAUSE_AGENTS"
        }

    def reset_panic_button(self):
        """Resets the manual panic state after operator review."""
        self._is_panic_activated = False
        logger.info("Panic button reset by operator.")

    def evaluate_pre_execution_safety(
        self,
        symbol: str,
        broker_price: float,
        oracle_price: float,
        pip_size: float,
        execution_latency_ms: float = 0.0
    ) -> Dict[str, Any]:
        """
        Evaluates execution health right before submitting an order to the broker.
        Called by auto_execution_worker._master_worker() before every trade execution.
        Returns dict with status='OK' or status='HALT' and the specific reason.

        Args:
            symbol: The asset being traded (e.g. 'EUR/USD')
            broker_price: Live price from the broker feed
            oracle_price: Independent oracle/analysis price (from data_streamer)
            pip_size: Pip size for this symbol (from get_pip_size())
            execution_latency_ms: Time from signal generation to this gate (ms)
        """
        now = time.time()

        # 1. Manual Panic Check (always first)
        if self._is_panic_activated:
            return {"status": "HALT", "reason": "MANUAL_PANIC_BUTTON_ACTIVE"}

        # 2. News Filter Heartbeat Check (with 5-minute boot grace period)
        time_since_boot = now - self._boot_time
        if time_since_boot > _BOOT_GRACE_PERIOD_SEC:
            time_since_news_ping = now - self._last_news_heartbeat
            if time_since_news_ping > _MAX_NEWS_HEARTBEAT_TIMEOUT_SEC:
                logger.warning(
                    "KillSwitch: News filter heartbeat timed out (%.1fs > %.1fs)",
                    time_since_news_ping, _MAX_NEWS_HEARTBEAT_TIMEOUT_SEC
                )
                return {
                    "status": "HALT",
                    "reason": f"NEWS_FILTER_HEARTBEAT_TIMEOUT_{time_since_news_ping:.1f}S"
                }

        # 3. Execution Latency Check (> 100ms)
        if execution_latency_ms > _MAX_LATENCY_MS:
            logger.warning(
                "KillSwitch: Execution latency spiked (%.1fms > %.1fms)",
                execution_latency_ms, _MAX_LATENCY_MS
            )
            return {"status": "HALT", "reason": f"LATENCY_SPIKE_{execution_latency_ms:.1f}MS"}

        # 4. Anti-Broker Manipulation Check (5-pip discrepancy vs independent oracle)
        if broker_price > 0 and oracle_price > 0 and pip_size > 0:
            price_diff_pips = abs(broker_price - oracle_price) / pip_size
            if price_diff_pips > _MAX_PRICE_DISCREPANCY_PIPS:
                logger.critical(
                    "🚨 BROKER MANIPULATION DETECTED on %s — "
                    "Broker=%.5f vs Oracle=%.5f (Diff: %.1f pips > %.1f pips threshold)",
                    symbol, broker_price, oracle_price, price_diff_pips, _MAX_PRICE_DISCREPANCY_PIPS
                )
                return {
                    "status": "HALT",
                    "reason": f"BROKER_MANIPULATION_DETECTED_{price_diff_pips:.1f}_PIPS_DISCREPANCY"
                }

        logger.debug(
            "KillSwitch: %s — ALL CHECKS PASSED. Broker=%.5f Oracle=%.5f Latency=%.1fms",
            symbol, broker_price, oracle_price, execution_latency_ms
        )
        return {"status": "OK", "reason": "SAFETY_CHECKS_PASSED"}

# Singleton Instance
hardened_kill_switch = HardenedKillSwitch()
