import asyncio
import logging
from storage import storage

logger = logging.getLogger("app_daemons")

async def _run_risk_microservice():
    global _risk_process
    consecutive_errors = 0
    try:
        while True:
            logger.info("Starting Risk Microservice on 127.0.0.1:8001...")
            import sys
            import subprocess
            import os
            
            minimal_env = {
                "RISK_INTERNAL_TOKEN": os.environ.get("RISK_INTERNAL_TOKEN", ""),
                "PATH": os.environ.get("PATH", ""),
                "PYTHONPATH": os.environ.get("PYTHONPATH", ""),
                # Windows-critical: Python stdlib (ssl, socket, tempfile) requires these
                "SYSTEMROOT": os.environ.get("SYSTEMROOT", ""),
                "VIRTUAL_ENV": os.environ.get("VIRTUAL_ENV", ""),
                "USERPROFILE": os.environ.get("USERPROFILE", ""),
            }
            
            _risk_process = subprocess.Popen(
                [sys.executable, "-m", "uvicorn", "risk_microservice:app", "--host", "127.0.0.1", "--port", "8001"],
                env=minimal_env
            )
            boot_time = time.time()

            # Report healthy once booted
            from system_health import health_registry
            await health_registry.report("risk_microservice", "GREEN", "Running on 127.0.0.1:8001")

            # Wait for process to exit using asyncio thread to avoid blocking main thread
            await asyncio.to_thread(_risk_process.wait)
            
            uptime = time.time() - boot_time
            if uptime > 30.0:
                # Ran for >30s before crashing — treat as transient, reset backoff
                consecutive_errors = 1
            else:
                consecutive_errors += 1
            sleep_time = min(60.0, 2.0 * (1.5 ** consecutive_errors))
            logger.critical(f"Risk Microservice CRASHED after {uptime:.0f}s. Restarting in {sleep_time:.1f} seconds...")

            # Report crash to health registry
            _h_state = "RED" if consecutive_errors >= 3 else "YELLOW"
            await health_registry.report("risk_microservice", _h_state,
                f"Crashed after {uptime:.0f}s — restarting in {sleep_time:.0f}s", {
                    "consecutive_crashes": consecutive_errors,
                    "last_uptime_s": round(uptime, 1),
                })

            await asyncio.sleep(sleep_time)
    except asyncio.CancelledError:
        if _risk_process:
            _risk_process.terminate()
        logger.info("Risk Microservice shutdown.")

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup checks and graceful shutdown."""
    
    # Generate an internal secure token for the Risk Microservice if not already defined
    if not os.environ.get("RISK_INTERNAL_TOKEN"):
        import secrets
        os.environ["RISK_INTERNAL_TOKEN"] = secrets.token_hex(32)

    # Start the Risk Guard Auto-Restarting Daemon (only if running locally)
    # If RISK_MICROSERVICE_URL points to a remote/different container (like http://risk:8001),
    # we don't start the subprocess because a dedicated service is running.
    microservice_url = os.environ.get("RISK_MICROSERVICE_URL", "http://127.0.0.1:8001")
    if "127.0.0.1" in microservice_url or "localhost" in microservice_url:
        global _risk_task
        _risk_task = asyncio.create_task(_run_risk_microservice())
        await asyncio.sleep(2)  # Give the microservice time to boot
    else:
        logger.info(f"Using external/containerized Risk Microservice at {microservice_url}")

    # ── STARTUP ──────────────────────────────
    logger.info("=" * 60)
    logger.info("  MEHD AI — Starting up")
    logger.info("=" * 60)

    import state
    await state.load_daily_spend_from_db()
    logger.info(f"✓ Daily API spend loaded: ${state.daily_api_spend_usd:.2f} / ${state.DAILY_API_BUDGET_USD:.2f}")

    # Self-check 1: Risk engine via Client
    try:
        health = await risk_client.get_account_health()
        logger.info("✓ Risk engine microservice loaded — balance: $%.2f", health.balance)
    except Exception as e:
        logger.critical("✗ Risk engine FAILED to load: %s", e)
        raise RuntimeError(f"Risk engine startup check failed: {e}") from e

    # FIX M3: Restore risk kernel state from storage backend (multi-replica aware)
    try:
        from risk_engine import HardRiskKernel
        kernel = HardRiskKernel()
        await kernel.restore_from_storage()
        logger.info("✓ Risk kernel state synced from storage backend")
    except Exception as e:
        logger.debug("Risk kernel storage restore skipped (non-fatal): %s", e)

    # Self-check 2: Audit trail
    try:
        logger.info("✓ Audit trail initialised — session: %s", audit.session_id)
    except Exception as e:
        logger.error("✗ Audit trail issue (non-fatal): %s", e)

    # Self-check 3: Den models
    try:
        model_status = await den_engine.health_check()
        responding = sum(1 for s in model_status.values() if s == "responding")
        logger.info("✓ The Den: %d/%d models responding", responding, len(model_status))
    except Exception as e:
        logger.error("✗ Den health check issue (non-fatal): %s", e)

    # Start data streamer
    try:
        await streamer.start()
        logger.info("✓ Market Data Streamer started")
    except Exception as e:
        logger.error("✗ Streamer startup issue (non-fatal): %s", e)

    # Start background loops (if not running in decoupled worker mode)
    if os.environ.get("DECOUPLED_WORKER_MODE", "").lower() == "true":
        logger.info("ℹ️ Running in DECOUPLED_WORKER_MODE — Background worker daemons bypassed on API server.")
    else:
        # Start Black Swan Monitor
        asyncio.create_task(black_swan.run_daemon())

        # Start the Broadcaster — the Underground Research Daemon
        # This runs 11 agents continuously in the background for all pairs,
        # so every user gets instant results instead of waiting 20 seconds.
        await broadcaster.start()
        
        # Start the Autopilot Execution Worker
        auto_execution_worker.start()

        # Start the Cleanup Worker to handle TTLs
        cleanup_worker.start()

        # Start the Weekly Scan Worker
        weekly_scan_worker.start()

        # Start the Truth Engine Worker (Scoreboard stats)
        truth_engine_worker.start()

        # Start the Personalization Worker (Chairman's Voice)
        personalization_worker.start()

        # Start the Sniper Engine (Virtual Stops)
        virtual_stop_worker.start()

        # Wire push notifications — "The Don Decided" FCM alerts for >= 92% conviction signals
        from push_notification_service import push_service
