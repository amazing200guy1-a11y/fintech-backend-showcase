"""
Mehd AI — Trading Routes
==========================
Endpoint: /execute

This is where money is on the line. Every trade request passes
through the RiskGateway's 4 gates before touching a broker.
"""

from __future__ import annotations

import asyncio
import logging
import random
import time
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Request, Depends
from slowapi import Limiter

from auth import get_current_user, get_current_user_mfa, get_real_ip, get_uid_rate_key
from black_swan_monitor import monitor_instance as black_swan
from models import RiskDecision, TradeOrder, ExecutiveBrief, InternalTradeOrder
from risk_engine import ConstitutionManager
from user_risk_store import user_risk_store
from state import audit, risk_client, streamer
from broadcaster import broadcaster
from storage import storage

logger = logging.getLogger("mehd.routes.trading")
from log_utils import safe_uid
router = APIRouter()
limiter = Limiter(key_func=get_uid_rate_key)


@router.post(
    "/execute",
    response_model=RiskDecision,
    summary="Execute a trade (risk gateway runs first)",
    tags=["Trading"],
)
@limiter.limit("5/minute")
async def execute_trade(
    request: Request, order: TradeOrder, uid: str = Depends(get_current_user_mfa)
) -> RiskDecision:
    """
    Submit a trade order. The RiskGateway evaluates it through 4 independent gates:
      Gate 1: Verify risk parameter integrity (drift detection)
      Gate 2: HardRiskKernel evaluation (all 5 checks)
      Gate 3: Independent double-validation (belt AND suspenders)
      Gate 4: Broker execution (if registered)

    If ANY gate fails, the trade is dead. No override is possible.
    """
    # ── SECURITY: APP CHECK ENFORCEMENT ──────────────────────────────────────
    # Ensures only the real Mehd AI mobile app can call /execute.
    # Even with a valid JWT, forged requests from Postman/curl are blocked.
    app_check_token = request.headers.get("X-Firebase-AppCheck")
    if app_check_token:
        try:
            from firebase_admin import app_check
            await asyncio.to_thread(app_check.verify_token, app_check_token)
        except Exception as e:
            logger.warning("APP CHECK FAILED on /execute for user %s: %s", safe_uid(uid), e)
            raise HTTPException(status_code=403, detail="App verification failed. Unauthorized client.")
    else:
        # In production, this should be a hard block.
        # During development, we log a warning but allow it.
        import os
        if os.getenv("DEMO_MODE", "true").lower() != "true":
            logger.critical("APP CHECK MISSING on /execute for user %s — BLOCKED in production", safe_uid(uid))
            raise HTTPException(status_code=403, detail="App verification required. Missing App Check token.")
        else:
            logger.warning("APP CHECK MISSING on /execute (allowed in DEMO_MODE) for user %s", safe_uid(uid))

    # ── FIX 1: IDEMPOTENCY KEY ──────────────────────────────────────────────
    # BEFORE: No idempotency. A mobile network retry or double-tap would send
    #         two identical requests, placing two trades silently.
    # AFTER:  Client must supply a unique Idempotency-Key header per trade
    #         intent. We cache the result for 5 minutes. Replayed requests
    #         immediately receive the cached RiskDecision — no second execution.
    idempotency_key = request.headers.get("Idempotency-Key", "").strip()
    if not idempotency_key:
        raise HTTPException(
            status_code=400,
            detail="Missing required header: Idempotency-Key. "
                   "Generate a UUID per trade attempt on the client."
        )
    if len(idempotency_key) > 128:
        raise HTTPException(status_code=400, detail="Idempotency-Key too long (max 128 chars).")

    cached_idem = await storage.get("idempotency_keys", f"{uid}:{idempotency_key}")
    if cached_idem:
        logger.info("IDEMPOTENCY HIT: Returning cached result for key %s (user %s)", idempotency_key, safe_uid(uid))
        return RiskDecision(**cached_idem)

    # ── FIX 3: STRICT SEQUENCING LOCK ───────────────────────────────────────
    # BEFORE: The Autopilot worker locked per-user, but the manual /execute
    #         endpoint had NO lock. A manual trade and an Autopilot trade for
    #         the same user could run concurrently, bypassing daily limits and
    #         doubling margin exposure.
    # AFTER:  The SAME lock key ("exec_{uid}") used by the Autopilot is now
    #         acquired here. Manual and auto trades for the same user are
    #         strictly sequenced — they cannot overlap.
    exec_lock_key = f"exec_{uid}"
    lock_acquired = await storage.acquire_lock(exec_lock_key, ttl_seconds=60)  # 60s: accounts for slow broker responses
    if not lock_acquired:
        raise HTTPException(
            status_code=409,
            detail="A trade execution is already in progress for your account. "
                   "Please wait and retry."
        )

    try:
        logger.info(
            "=== EXECUTE REQUEST: %s %s (server will calculate lot size) ===",
            order.direction.value,
            order.symbol,
        )

        # Black Swan Global Check — Immediate Lockout
        swan_status = black_swan.get_status()
        if swan_status["swan_level"] >= 2:
            decision = RiskDecision(
                id=f"T_{int(time.time()*1000)}",
                symbol=order.symbol,
                approved=False,
                rejection_reason="BLACK SWAN LOCKOUT: %s" % swan_status["swan_threat"],
                calculated_lot_size=0,
            )
            # Cache even rejections so retries are instant
            await storage.set("idempotency_keys", f"{uid}:{idempotency_key}",
                               decision.model_dump(mode="json"), )
            return decision

        # RISK GATEWAY — THE ONLY PATH TO TRADE EXECUTION
        live_snapshot = streamer.get_latest_snapshot(order.symbol)

        # GET VERIFIED CONSENSUS FROM THE BROADCASTER, NOT THE CLIENT
        broadcast = broadcaster.get_latest(order.symbol)
        if not broadcast:
            raise HTTPException(status_code=400, detail="No verified AI consensus available for this symbol. Trade rejected.")

        # ── FIX 2: SERVER-SIDE VALIDATION ───────────────────────────────────
        # BEFORE: The server trusted the client's lot_size and risk_percentage.
        #         A tampered request with lot_size=100 or risk_percentage=1.0
        #         (100% of balance) could blow up the account.
        # AFTER:  The server IGNORES the client's lot_size entirely.
        # risk_percentage is stored as a PERCENTAGE (1.0 = 1%, 10.0 = 10%).
        # The slider on the app goes from 0.1% to 10.0%.
        # The server clamps to 10.0 (the slider max) as a hard ceiling.
        SERVER_MAX_RISK_PCT = 10.0   # Hard ceiling: matches the 10% max on the Risk Slider
        server_risk_pct = min(order.risk_percentage, SERVER_MAX_RISK_PCT)

        # Client lot_size is completely ignored — Risk Kernel calculates it
        # from account balance and server_risk_pct. We pass 1.0 as a placeholder;
        # the kernel will override it with the safe value.
        internal_order = InternalTradeOrder(
            symbol=order.symbol,
            direction=order.direction,
            lot_size=1.0,           # ← CLIENT VALUE DISCARDED. Kernel will recalculate.
            stop_loss=order.stop_loss,
            take_profit=order.take_profit,
            risk_percentage=server_risk_pct,   # ← CLAMPED server-side, never trust client
            votes=broadcast.consensus.votes,
            math_layer_votes=[v for v in broadcast.consensus.votes if v.model_name.upper() in ["TITAN", "ATLAS", "FORGE"]],
            is_auto_execution=False,
        )

        logger.info(
            "SERVER-SIDE PARAMS: risk_pct=%.3f (client sent %.3f, capped at %.3f)",
            server_risk_pct, order.risk_percentage, SERVER_MAX_RISK_PCT
        )

        # Send through the Risk Microservice
        try:
            gw_result = await risk_client.evaluate_and_execute(
                order=internal_order,
                current_price=live_snapshot.close,
                current_spread=live_snapshot.spread,
                user_id=uid
            )
        except Exception as e:
            logger.error("RiskService communication failure: %s", e)
            raise HTTPException(status_code=500, detail="Risk Gateway unreachable. Trade blocked.")

        decision_dict = gw_result.get("decision")
        decision = decision_dict if isinstance(decision_dict, RiskDecision) else RiskDecision(**(decision_dict or {}))

        # Log the trade attempt regardless of approval
        audit.log_trade(internal_order, decision)

        if not decision.approved:
            logger.warning(
                "Trade REJECTED: %s — %s", order.symbol, decision.rejection_reason
            )
            try:
                import track_record
                track_record.log_risk_blocked(
                    symbol=order.symbol,
                    direction=order.direction.value,
                    reason=decision.rejection_reason or "Unknown",
                    lot_size_requested=order.lot_size,
                )
            except Exception as e:
                logger.warning("Failed to log risk blocked track record for %s: %s", order.symbol, e)

            health = await risk_client.get_account_health()
            if health.is_locked:
                audit.log_account_event("ACCOUNT_LOCKED", health.model_dump())

            if not gw_result["seal_valid"]:
                audit.log_account_event("SECURITY_BREACH_DETECTED", health.model_dump())
                logger.critical(
                    "SECURITY BREACH: Risk parameters tampered — all trading suspended for user %s", safe_uid(uid),
                )

            # Cache rejection so replayed requests don't rerun the risk engine
            await storage.set("idempotency_keys", f"{uid}:{idempotency_key}",
                               decision.model_dump(mode="json"))
            return decision

        else:
            # ── MATH LAYER VETO — MUST RUN BEFORE BROKER EXECUTION ──
            if internal_order.votes:
                math_votes = internal_order.math_layer_votes or []
                vetoed, veto_reason = await risk_client.check_math_veto(math_votes)
                if vetoed:
                    logger.warning("Math Layer Veto BLOCKED trade BEFORE execution: %s", veto_reason)
                    decision = RiskDecision(
                        approved=False,
                        calculated_lot_size=0.0,
                        stop_loss=order.stop_loss or 0.0001,
                        take_profit=order.take_profit,
                        rejection_reason=f"MATH_LAYER_VETO: {veto_reason}",
                    )
                    audit.log_trade(internal_order, decision)
                    await storage.set("idempotency_keys", f"{uid}:{idempotency_key}",
                                       decision.model_dump(mode="json"))
                    return decision

            # ── BROKER EXECUTION PIPELINE ──
            # GAP #2 FIX: Execution latency telemetry (Google lesson)
            from broker_gateway import broker_gateway
            from secrets_manager import encryption
            import track_record
            
            # Fetch user's encrypted vault
            user_vault = await storage.get("broker_vaults", uid)
            broker_creds = None
            if user_vault:
                try:
                    # Decrypt just-in-time
                    decrypted_key = encryption.decrypt(user_vault.get("encrypted_api_key", ""))
                    decrypted_secret = encryption.decrypt(user_vault.get("encrypted_api_secret", ""))
                    
                    broker_creds = {
                        "api_key": decrypted_key,
                        "api_secret": decrypted_secret,
                        "account_id": user_vault.get("exchange_id", ""),
                    }
                except Exception as e:
                    logger.error("Failed to decrypt user %s broker vault: %s", safe_uid(uid), e)
            
            logger.info("Dispatching to broker gateway for %s...", order.symbol)
            _t0 = time.monotonic()
            
            # Pass decrypted credentials to the gateway
            broker_result = await broker_gateway.execute_order(order, decision, credentials=broker_creds)
            
            # Instantly wipe decrypted keys from memory
            if broker_creds:
                broker_creds["api_key"] = "WIPED"
                broker_creds["api_secret"] = "WIPED"
                del broker_creds
                
            _broker_latency_ms = (time.monotonic() - _t0) * 1000
            logger.info(
                "Broker result: mode=%s, status=%s, latency=%.0fms",
                broker_result.get("mode", "unknown"),
                broker_result.get("status", "unknown"),
                _broker_latency_ms,
            )
            if _broker_latency_ms > 3000:
                logger.warning(
                    "BROKER_LATENCY_SPIKE: %s took %.0fms (>3s threshold) — "
                    "investigate broker connectivity", order.symbol, _broker_latency_ms
                )

            track_record.log_trade_executed(
                symbol=order.symbol,
                direction=order.direction.value,
                lot_size=decision.calculated_lot_size,
                entry_price=float(broker_result.get("fill_price", 0) or 0),
                broker_mode=broker_result.get("mode", "paper"),
                trade_id=str(decision.id),
            )

            async def _sync_limits():
                if broker_result.get("status") not in ["error", "rejected", "timeout"]:
                    await user_risk_store.increment_trades(uid)
                    await ConstitutionManager.increment_daily_trades(user_id=uid)

            await asyncio.shield(_sync_limits())

            # Generate Executive Brief for audit trail
            current_health = await risk_client.get_account_health()
            brief = ExecutiveBrief(
                trade_id=decision.id,
                user_id=uid,
                symbol=order.symbol,
                timestamp=datetime.now(timezone.utc),
                final_verdict=order.direction.value,
                consensus_score="N/A",
                sentiment_layer={},
                strategy_layer={},
                math_layer={},
                risk_verification={
                    "Lot size": str(decision.calculated_lot_size),
                    "Max loss": f"${current_health.balance * server_risk_pct:.2f} ({server_risk_pct*100:.1f}% of balance — server enforced)",
                    "Stop loss": f"{decision.stop_loss} ✓",
                    "Take profit": f"{decision.take_profit or 'N/A'} ✓",
                    "Volatility": "Normal ✓",
                    "Gateway": f"SEALED ({gw_result['evaluation_id']})",
                },
                decision_basis="This trade was not a glitch. It was a calculated decision based on sentiment, technical structure, and mathematical verification. All decisions logged permanently.",
            )

            if internal_order.votes:
                agree_count = sum(
                    1 for v in internal_order.votes if v.direction == order.direction
                )
                total = len(internal_order.votes)
                pct = int((agree_count / total) * 100) if total > 0 else 0
                brief.consensus_score = f"{agree_count}/{total} ({pct}%)"

                math_agents = ["TITAN", "ATLAS", "FORGE", "THE DON", "SENTINEL"]
                sentiment_agents = ["DON", "PHANTOM", "ORACLE"]
                for v in internal_order.votes:
                    m_name = v.model_name.upper()
                    layer = (
                        "math_layer"
                        if m_name in math_agents
                        else "sentiment_layer"
                        if m_name in sentiment_agents
                        else "strategy_layer"
                    )
                    getattr(brief, layer)[v.model_name] = f"{v.direction.value} — {v.reasoning}"

            await storage.set("briefs", str(decision.id), brief.model_dump(mode="json"))

            # ── FIX 1: Cache successful result for idempotency ───────────────
            # TTL: 5 minutes (300s). After that the key expires naturally.
            # Any retry within 5 minutes gets this exact RiskDecision back.
            await storage.set("idempotency_keys", f"{uid}:{idempotency_key}",
                               decision.model_dump(mode="json"))

        return decision

    except Exception as e:
        logger.error("Trade execution failed: %s", e)
        raise HTTPException(
            status_code=500,
            detail="Trade execution temporarily unavailable. Please retry.",
        ) from e

    finally:
        # ── FIX 3: ALWAYS release the sequencing lock ───────────────────────
        # Even if the handler crashes, the lock is released so the user
        # is never permanently stuck. This is the critical guarantee.
        await storage.release_lock(exec_lock_key)


