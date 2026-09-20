"""
Mehd AI — MAM Dark Pool & Master Ledger Distribution Stress Tests
=================================================================
Stress tests the institutional MAM dark pool engine:
1. 500-user block order execution & tier priority gating.
2. Fractional partial fills & 0.01 micro-lot floor enforcement.
3. Leftover dust absorption into FirmInventory (zero-loss dark pool).
4. Precision tier session expiry auto-disarm.
5. Currency sector correlation guard.
6. Broker override asset class filtering.
7. Orphan trade recovery.
"""

import asyncio
from datetime import datetime, timezone, timedelta
import json
import pytest

from storage import storage
from models import AutopilotConfig, FirmInventory
from market_models import BrokerRiskConfig
import mam_ledger_distribution
from mam_ledger_distribution import run_ledger_distribution_loop


class DummyWorker:
    """Mock auto-execution worker for ledger distribution testing."""
    def __init__(self):
        self._running = True
        self.briefing_logs = []

    def _reset_stale_counters(self, cfg: AutopilotConfig) -> AutopilotConfig:
        return cfg

    async def _log_to_morning_briefing(self, user_id: str, symbol: str, direction: str, status: str, reason: str):
        self.briefing_logs.append({
            "user_id": user_id,
            "symbol": symbol,
            "direction": direction,
            "status": status,
            "reason": reason,
        })


@pytest.fixture(autouse=True)
def reset_storage_and_patch_sleep(monkeypatch):
    """Resets memory storage and patches asyncio.sleep for instant test execution."""
    if hasattr(storage, "_store"):
        storage._store.clear()

    worker_holder = {"worker": None}

    async def fast_sleep(seconds: float):
        if seconds >= 20 and worker_holder["worker"] is not None:
            # End the distribution loop cleanly after one processing pass
            worker_holder["worker"]._running = False
        return

    monkeypatch.setattr(mam_ledger_distribution.asyncio, "sleep", fast_sleep)
    return worker_holder


class TestMAM500UserBlockOrderExecution:
    """Simulates 500 users streaming batch with tier gating and priority sorting."""

    def test_500_user_block_order_execution_and_tier_gating(self, reset_storage_and_patch_sleep):
        worker = DummyWorker()
        reset_storage_and_patch_sleep["worker"] = worker

        async def run_test():
            # Setup 500 users:
            # - 100 Sovereign (tier="sovereign", lot=0.10)
            # - 100 Precision (tier="precision", session_armed=True, lot=0.05)
            # - 100 Core (tier="core", lot=0.05) -> skipped (1-Tap Manual Strike only)
            # - 100 Observer (tier="observer", lot=0.01) -> skipped
            # - 100 Disabled/Frozen Sovereign -> skipped
            for i in range(100):
                uid = f"sov_{i}"
                cfg = AutopilotConfig(
                    user_id=uid, enabled=True, frozen=False, preferred_lot_size=0.10
                )
                raw = json.loads(cfg.model_dump_json())
                raw["tier"] = "sovereign"
                await storage.set("autopilot_configs", uid, raw)

            for i in range(100):
                uid = f"prec_{i}"
                cfg = AutopilotConfig(
                    user_id=uid, enabled=True, frozen=False, preferred_lot_size=0.05,
                    session_armed=True,
                )
                raw = json.loads(cfg.model_dump_json())
                raw["tier"] = "precision"
                await storage.set("autopilot_configs", uid, raw)

            for i in range(100):
                uid = f"core_{i}"
                cfg = AutopilotConfig(
                    user_id=uid, enabled=True, frozen=False, preferred_lot_size=0.05
                )
                raw = json.loads(cfg.model_dump_json())
                raw["tier"] = "core"
                await storage.set("autopilot_configs", uid, raw)

            for i in range(100):
                uid = f"obs_{i}"
                cfg = AutopilotConfig(
                    user_id=uid, enabled=True, frozen=False, preferred_lot_size=0.01
                )
                raw = json.loads(cfg.model_dump_json())
                raw["tier"] = "observer"
                await storage.set("autopilot_configs", uid, raw)

            for i in range(100):
                uid = f"dis_{i}"
                cfg = AutopilotConfig(
                    user_id=uid, enabled=False, frozen=(i % 2 == 0), preferred_lot_size=0.10
                )
                raw = json.loads(cfg.model_dump_json())
                raw["tier"] = "sovereign"
                await storage.set("autopilot_configs", uid, raw)

            # 100 Sovereign * 0.10 = 10.0 lots
            # 100 Precision * 0.05 = 5.0 lots
            # Total demand = 15.0 lots
            task_id = "task_500_block"
            receipt = {
                "symbol": "EURUSD",
                "direction": "BUY",
                "fill_price": 1.0850,
                "fill_ratio": 1.0,
                "is_closed": False,
                "total_volume_lots": 15.0,
            }
            await storage.set("master_receipts", task_id, receipt)
            task_data = {
                "status": "PENDING",
                "users_processed": 0,
                "processed_user_ids": [],
                "total_allocated_lots": 0.0,
            }
            await storage.set("ledger_tasks", task_id, task_data)

            # Execute ledger loop
            await run_ledger_distribution_loop(worker)
            await asyncio.sleep(0.01)

            # Assert task completion
            completed_task = await storage.get("ledger_tasks", task_id)
            assert completed_task["status"] == "COMPLETED"
            assert completed_task["users_processed"] == 200
            assert completed_task["total_allocated_lots"] == pytest.approx(15.0, 0.001)

            # Verify Sovereign user execution
            sov_cfg_raw = await storage.get("autopilot_configs", "sov_0")
            assert "EURUSD" in sov_cfg_raw["open_auto_positions"]
            assert sov_cfg_raw["active_allocations"]["EURUSD"] == 0.10
            assert sov_cfg_raw["daily_auto_trades_count"] == 1

            # Verify Precision user execution
            prec_cfg_raw = await storage.get("autopilot_configs", "prec_0")
            assert "EURUSD" in prec_cfg_raw["open_auto_positions"]
            assert prec_cfg_raw["active_allocations"]["EURUSD"] == 0.05

            # Verify Core user was skipped
            core_cfg_raw = await storage.get("autopilot_configs", "core_0")
            assert "EURUSD" not in core_cfg_raw["open_auto_positions"]
            assert core_cfg_raw["daily_auto_trades_count"] == 0

            # Verify zero dark pool unhedged exposure
            firm_inv = await storage.get("firm_inventory", "EURUSD")
            assert firm_inv is None or firm_inv.get("net_exposure_lots", 0.0) == 0.0

        asyncio.run(run_test())


class TestFractionalPartialFillAndMicroLotDust:
    """Validates partial fills down to the 0.01 micro-lot floor."""

    def test_partial_fill_scaling_and_sub_micro_lot_drop(self, reset_storage_and_patch_sleep):
        worker = DummyWorker()
        reset_storage_and_patch_sleep["worker"] = worker

        async def run_test():
            # User 1: preferred 0.10 -> at 0.80 fill = 0.08 (Valid)
            u1_cfg = AutopilotConfig(user_id="u1", enabled=True, preferred_lot_size=0.10)
            u1_raw = json.loads(u1_cfg.model_dump_json())
            u1_raw["tier"] = "sovereign"
            await storage.set("autopilot_configs", "u1", u1_raw)

            # User 2: preferred 0.01 micro-lot -> at 0.80 fill = round(0.008, 2) = 0.01 (Valid)
            u2_cfg = AutopilotConfig(user_id="u2", enabled=True, preferred_lot_size=0.01)
            u2_raw = json.loads(u2_cfg.model_dump_json())
            u2_raw["tier"] = "sovereign"
            await storage.set("autopilot_configs", "u2", u2_raw)

            # User 3: preferred 0.01 micro-lot -> at 0.40 fill = round(0.004, 2) = 0.00 < 0.01 (DROPPED)
            u3_cfg = AutopilotConfig(user_id="u3", enabled=True, preferred_lot_size=0.01)
            u3_raw = json.loads(u3_cfg.model_dump_json())
            u3_raw["tier"] = "sovereign"
            await storage.set("autopilot_configs", "u3", u3_raw)

            # Task with 0.40 fill ratio
            task_id = "task_partial_fill"
            receipt = {
                "symbol": "GBPUSD",
                "direction": "SELL",
                "fill_price": 1.2750,
                "fill_ratio": 0.40,
                "is_closed": False,
                "total_volume_lots": 0.10,
            }
            await storage.set("master_receipts", task_id, receipt)
            task_data = {
                "status": "PENDING",
                "users_processed": 0,
                "processed_user_ids": [],
                "total_allocated_lots": 0.0,
            }
            await storage.set("ledger_tasks", task_id, task_data)

            await run_ledger_distribution_loop(worker)

            # User 1: 0.10 * 0.40 = 0.04 lots
            u1_res = await storage.get("autopilot_configs", "u1")
            assert u1_res["active_allocations"]["GBPUSD"] == 0.04
            assert "GBPUSD" in u1_res["open_auto_positions"]

            # User 3: dropped due to < 0.01 minimum lot
            u3_res = await storage.get("autopilot_configs", "u3")
            assert "GBPUSD" not in u3_res["open_auto_positions"]

            # Check morning briefing log for User 3
            dropped_logs = [l for l in worker.briefing_logs if l["user_id"] == "u3"]
            assert len(dropped_logs) == 1
            assert dropped_logs[0]["status"] == "DROPPED"
            assert "below the 0.01 minimum lot requirement" in dropped_logs[0]["reason"]

        asyncio.run(run_test())


class TestDarkPoolZeroLossAbsorption:
    """Verifies leftover fractional dust and unhedged lots are absorbed by FirmInventory."""

    def test_firm_inventory_absorbs_unhedged_lots(self, reset_storage_and_patch_sleep):
        worker = DummyWorker()
        reset_storage_and_patch_sleep["worker"] = worker

        async def run_test():
            # 5 Sovereign users each requesting 0.10 lots = 0.50 lots total
            for i in range(5):
                uid = f"sov_dp_{i}"
                cfg = AutopilotConfig(user_id=uid, enabled=True, preferred_lot_size=0.10)
                raw = json.loads(cfg.model_dump_json())
                raw["tier"] = "sovereign"
                await storage.set("autopilot_configs", uid, raw)

            # Broker executed block order of 2.00 lots (liquidity buffer / firm participation)
            task_id = "task_dark_pool_gold"
            total_broker_lots = 2.00
            receipt = {
                "symbol": "XAUUSD",
                "direction": "BUY",
                "fill_price": 2650.50,
                "fill_ratio": 1.0,
                "is_closed": False,
                "total_volume_lots": total_broker_lots,
            }
            await storage.set("master_receipts", task_id, receipt)
            task_data = {
                "status": "PENDING",
                "users_processed": 0,
                "processed_user_ids": [],
                "total_allocated_lots": 0.0,
            }
            await storage.set("ledger_tasks", task_id, task_data)

            await run_ledger_distribution_loop(worker)

            task_completed = await storage.get("ledger_tasks", task_id)
            allocated = task_completed["total_allocated_lots"]
            assert allocated == pytest.approx(0.50, 0.001)

            # Unhedged: 2.00 - 0.50 = 1.50 lots absorbed by FirmInventory
            firm_inv_raw = await storage.get("firm_inventory", "XAUUSD")
            assert firm_inv_raw is not None
            firm_inv = FirmInventory.model_validate(firm_inv_raw)
            assert firm_inv.net_exposure_lots == pytest.approx(1.50, 0.001)

            # Conservation of lots: Broker Lots == Allocated + Firm Exposure
            assert total_broker_lots == pytest.approx(allocated + firm_inv.net_exposure_lots, 0.0001)

        asyncio.run(run_test())


class TestPrecisionSessionExpiryAndFilters:
    """Verifies session expiration disarming, currency sector caps, and broker asset filters."""

    def test_precision_session_expiry_disarms_user(self, reset_storage_and_patch_sleep):
        worker = DummyWorker()
        reset_storage_and_patch_sleep["worker"] = worker

        async def run_test():
            # Expired session: armed_until was 15 minutes ago
            past_time = (datetime.now(timezone.utc) - timedelta(minutes=15)).isoformat()
            cfg = AutopilotConfig(
                user_id="prec_exp",
                enabled=True,
                session_armed=True,
                session_armed_until=past_time,
                preferred_lot_size=0.10,
            )
            raw = json.loads(cfg.model_dump_json())
            raw["tier"] = "precision"
            await storage.set("autopilot_configs", "prec_exp", raw)

            task_id = "task_expiry"
            receipt = {
                "symbol": "USDJPY",
                "direction": "BUY",
                "fill_price": 155.00,
                "fill_ratio": 1.0,
                "is_closed": False,
                "total_volume_lots": 1.0,
            }
            await storage.set("master_receipts", task_id, receipt)
            task_data = {"status": "PENDING", "processed_user_ids": []}
            await storage.set("ledger_tasks", task_id, task_data)

            await run_ledger_distribution_loop(worker)

            # User must be disarmed and skipped
            updated_raw = await storage.get("autopilot_configs", "prec_exp")
            assert updated_raw["session_armed"] is False
            assert updated_raw["session_armed_until"] is None
            assert "USDJPY" not in updated_raw["open_auto_positions"]

        asyncio.run(run_test())

    def test_currency_sector_correlation_cap(self, reset_storage_and_patch_sleep):
        worker = DummyWorker()
        reset_storage_and_patch_sleep["worker"] = worker

        async def run_test():
            # User already has 2 positions involving USD
            cfg = AutopilotConfig(
                user_id="sov_corr",
                enabled=True,
                open_auto_positions=["EURUSD", "GBPUSD"],
                preferred_lot_size=0.10,
            )
            raw = json.loads(cfg.model_dump_json())
            raw["tier"] = "sovereign"
            await storage.set("autopilot_configs", "sov_corr", raw)

            task_id = "task_usd_corr"
            receipt = {
                "symbol": "USDJPY",
                "direction": "BUY",
                "fill_price": 156.00,
                "fill_ratio": 1.0,
                "is_closed": False,
                "total_volume_lots": 0.50,
            }
            await storage.set("master_receipts", task_id, receipt)
            task_data = {"status": "PENDING", "processed_user_ids": []}
            await storage.set("ledger_tasks", task_id, task_data)

            await run_ledger_distribution_loop(worker)

            # User skipped due to USD correlation limit (already has 2 USD pairs)
            updated_raw = await storage.get("autopilot_configs", "sov_corr")
            assert "USDJPY" not in updated_raw["open_auto_positions"]

        asyncio.run(run_test())

    def test_broker_override_asset_class_filter(self, reset_storage_and_patch_sleep):
        worker = DummyWorker()
        reset_storage_and_patch_sleep["worker"] = worker

        async def run_test():
            # User only allows FOREX on their broker
            broker_cfg = BrokerRiskConfig(
                broker_id="oanda_fx",
                allowed_asset_classes=["FOREX"],
                is_active=True,
            )
            cfg = AutopilotConfig(
                user_id="sov_broker_filter",
                enabled=True,
                broker_overrides=[broker_cfg],
                preferred_lot_size=0.05,
            )
            raw = json.loads(cfg.model_dump_json())
            raw["tier"] = "sovereign"
            await storage.set("autopilot_configs", "sov_broker_filter", raw)

            # Block trade for Gold (METALS)
            task_id = "task_gold_filter"
            receipt = {
                "symbol": "XAUUSD",
                "direction": "BUY",
                "fill_price": 2650.0,
                "fill_ratio": 1.0,
                "is_closed": False,
                "total_volume_lots": 0.50,
            }
            await storage.set("master_receipts", task_id, receipt)
            task_data = {"status": "PENDING", "processed_user_ids": []}
            await storage.set("ledger_tasks", task_id, task_data)

            await run_ledger_distribution_loop(worker)

            # User skipped because broker override does not allow METALS
            updated_raw = await storage.get("autopilot_configs", "sov_broker_filter")
            assert "XAUUSD" not in updated_raw["open_auto_positions"]

        asyncio.run(run_test())


class TestOrphanTradeRecovery:
    """Verifies that interrupted tasks with status=PROCESSING are recovered to PENDING on boot."""

    def test_orphan_task_recovered_to_pending(self, reset_storage_and_patch_sleep):
        worker = DummyWorker()
        reset_storage_and_patch_sleep["worker"] = worker

        async def run_test():
            # Setup a stuck task from a prior crashed run
            stuck_task_id = "task_stuck_orphan"
            await storage.set("ledger_tasks", stuck_task_id, {
                "status": "PROCESSING",
                "users_processed": 0,
                "processed_user_ids": [],
            })

            # Normal receipt for this task
            await storage.set("master_receipts", stuck_task_id, {
                "symbol": "EURUSD",
                "direction": "BUY",
                "fill_price": 1.0850,
                "total_volume_lots": 1.0,
            })

            # Setup 1 user
            cfg = AutopilotConfig(user_id="sov_orphan", enabled=True, preferred_lot_size=0.10)
            raw = json.loads(cfg.model_dump_json())
            raw["tier"] = "sovereign"
            await storage.set("autopilot_configs", "sov_orphan", raw)

            # Run loop
            await run_ledger_distribution_loop(worker)

            # Stuck task should have been recovered to PENDING and then executed to COMPLETED
            recovered = await storage.get("ledger_tasks", stuck_task_id)
            assert recovered["status"] == "COMPLETED"
            assert recovered["users_processed"] == 1

        asyncio.run(run_test())
