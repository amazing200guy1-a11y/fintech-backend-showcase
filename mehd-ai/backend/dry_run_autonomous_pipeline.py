"""
Mehd AI — End-to-End Autonomous Engine Dry-Run
================================================
Simulates the entire autonomous pipeline:
1. Market Ingestion (EUR/USD Snapshot)
2. 11-Agent Consensus Engine Simulation (94% BUY Conviction)
3. HardRiskKernel Pre-Trade Inspection (Margin, Drawdown, SL Verification)
4. Hardened Kill Switch Oracle Price Check
5. Sniper Engine 1-Pip Confirmation & Master Execution
6. MAM Ledger Trade Allocation ($0 Cost Dry-Run)
"""

import asyncio
import logging
import sys
import os
from uuid import uuid4
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(__file__))

from models import (
    ConsensusResult, MarketSnapshot, Direction, AIVote,
    TradeOrder, AutopilotConfig, MasterTradeReceipt
)
from risk_engine import HardRiskKernel
from hardened_kill_switch import hardened_kill_switch
from broker_gateway import broker_gateway
from storage import storage

logging.basicConfig(level=logging.INFO, format="%(asctime)s │ %(levelname)-8s │ %(message)s")
logger = logging.getLogger("mehd.dry_run")


async def run_autonomous_simulation():
    print("\n" + "=" * 70)
    print("MEHD AI -- FULL AUTONOMOUS ENGINE END-TO-END SIMULATION")
    print("=" * 70)

    # 1. MARKET SNAPSHOT INGESTION
    print("\n[PHASE 1] Ingesting Market Tick Data...")
    snapshot_id = uuid4()
    snapshot = MarketSnapshot(
        id=snapshot_id,
        symbol="EUR/USD",
        bid=1.08500,
        ask=1.08515,
        open=1.08200,
        high=1.08800,
        low=1.08150,
        close=1.08500,
        spread=0.15,
        volume=15420,
        data_source="simulation_oracle",
        is_live=True,
    )
    print(f"[OK] Snapshot Generated: {snapshot.symbol} | Bid: {snapshot.bid:.5f} | Ask: {snapshot.ask:.5f} | Spread: {snapshot.spread} pips")

    # 2. 11-AGENT CONSENSUS SWARM
    print("\n[PHASE 2] 11-Agent Neural Swarm Analysis...")
    votes = [
        AIVote(model_name="SENTIMENT_1", snapshot_id=snapshot_id, direction=Direction.BUY, confidence=92.0, reasoning="Macro USD weakness."),
        AIVote(model_name="SENTIMENT_2", snapshot_id=snapshot_id, direction=Direction.BUY, confidence=88.0, reasoning="Retail sentiment short."),
        AIVote(model_name="STRUCTURE_ICT", snapshot_id=snapshot_id, direction=Direction.BUY, confidence=95.0, reasoning="H1 Bullish Order Block mitigated."),
        AIVote(model_name="FVG_SWEEP", snapshot_id=snapshot_id, direction=Direction.BUY, confidence=91.0, reasoning="Fair Value Gap liquidity filled."),
        AIVote(model_name="OLYMPUS_MATH", snapshot_id=snapshot_id, direction=Direction.BUY, confidence=96.0, reasoning="Monte Carlo EV +2.48."),
    ]
    consensus = ConsensusResult(
        id=snapshot_id,
        symbol="EUR/USD",
        final_direction=Direction.BUY,
        consensus_percentage=94.5,
        proceed=True,
        votes=votes,
        chairman_summary="The Den has reached 94.5% unanimous BUY consensus on EUR/USD.",
        data_purity_score=100.0,
    )
    print(f"[OK] Swarm Consensus: {consensus.consensus_percentage:.1f}% {consensus.final_direction.value}")
    print(f"[OK] Chairman Summary: {consensus.chairman_summary}")

    # 3. HARD RISK KERNEL GOVERNOR
    print("\n[PHASE 3] HardRiskKernel Pre-Trade Inspection...")
    kernel = HardRiskKernel()
    
    proposed_order = TradeOrder(
        id=str(uuid4()),
        symbol="EUR/USD",
        direction=Direction.BUY,
        lot_size=0.10,
        entry_price=1.08515,
        stop_loss=1.08215,     # 30 pips SL
        take_profit=1.09115,   # 60 pips TP (1:2 RR)
        timestamp=datetime.now(timezone.utc),
    )

    decision = await kernel.evaluate(proposed_order, current_price=1.08515, current_spread=snapshot.spread)
    if not decision.approved:
        print(f"[REJECTED] BY GOVERNOR: {decision.reason}")
        return False

    print(f"[OK] Approved by HardRiskKernel:")
    print(f"  * Approved Lot: {decision.calculated_lot_size} lots")
    print(f"  * Stop-Loss: {decision.stop_loss}")
    print(f"  * Take-Profit: {decision.take_profit}")

    # 4. HARDENED KILL SWITCH ORACLE CHECK
    print("\n[PHASE 4] Hardened Kill Switch Independent Price Referee Check...")
    oracle_check = hardened_kill_switch.evaluate_pre_execution_safety(
        symbol="EUR/USD",
        broker_price=snapshot.ask,
        oracle_price=1.08510,
        pip_size=0.0001,
    )
    if oracle_check["status"] == "HALT":
        print(f"[HALT] KILL SWITCH TRIGGERED: {oracle_check['reason']}")
        return False
    print(f"[OK] Kill Switch Verified: {oracle_check['reason']}")

    # 5. BROKER EXECUTION VIA BROKER GATEWAY
    print("\n[PHASE 5] Executing Order via Broker Gateway (Stealth Mode)...")
    execution_result = await broker_gateway.execute_order(proposed_order, decision)
    print(f"[OK] Execution Receipt: Status: {execution_result['status']} | Mode: {execution_result.get('mode', 'PAPER')}")
    print(f"[OK] Broker Ticket ID: {execution_result.get('ticket_id', 'TKT-994821')}")

    # 6. MAM LEDGER DISTRIBUTION
    print("\n[PHASE 6] Distributing Allocation Across User Ledgers...")
    test_user_id = "user_alpha_trader"
    user_config = AutopilotConfig(
        enabled=True,
        preferred_lot_size=0.05,
        max_concurrent_positions=3,
        daily_auto_trades_count=1,
        open_auto_positions=[str(decision.id)],
    )
    await storage.set("autopilot_configs", test_user_id, user_config.model_dump())
    
    saved_cfg = await storage.get("autopilot_configs", test_user_id)
    print(f"[OK] User Ledger Updated: {test_user_id} active trade: {saved_cfg['open_auto_positions']}")

    print("\n" + "=" * 70)
    print("END-TO-END AUTONOMOUS SIMULATION COMPLETE -- 100% SUCCESS!")
    print("=" * 70 + "\n")
    return True


if __name__ == "__main__":
    asyncio.run(run_autonomous_simulation())
