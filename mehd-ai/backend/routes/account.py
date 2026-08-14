"""
Mehd AI — Account Routes
===========================
Endpoints: /account_health, /gateway/status, /constitution,
           /account/delete (GDPR)

Everything about the trader's account state and governance.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Request, Depends
from slowapi import Limiter

from auth import get_current_user, get_real_ip, get_uid_rate_key
from models import AccountHealth, AppConstitution, Watchlist
from risk_engine import ConstitutionManager
from state import risk_client
from storage import storage
from secrets_manager import encryption
from pydantic import BaseModel

logger = logging.getLogger("mehd.routes.account")
router = APIRouter()
limiter = Limiter(key_func=get_uid_rate_key)

class BrokerCredentialsPayload(BaseModel):
    exchange_id: str
    api_key: str
    api_secret: str


@router.get(
    "/account_health",
    response_model=AccountHealth,
    summary="Get current account status",
    tags=["Account"],
)
@limiter.limit("30/minute")
async def get_account_health(request: Request, uid: str = Depends(get_current_user)) -> AccountHealth:
    """Returns the real-time account health snapshot."""
    return await risk_client.get_account_health()


@router.get(
    "/gateway/status",
    summary="Risk Gateway integrity status",
    tags=["Security"],
)
async def get_gateway_status(uid: str = Depends(get_current_user)):
    """
    Returns the RiskGateway's health status:
    - SEALED = all risk parameters match boot-time snapshot (safe)
    - COMPROMISED = parameters have drifted from boot snapshot (trades blocked)
    """
    return await risk_client.get_gateway_status()


@router.get(
    "/compliance",
    summary="Compliance status snapshot",
    tags=["Account"],
)
@limiter.limit("20/minute")
async def get_compliance(request: Request, uid: str = Depends(get_current_user)):
    """
    Returns the platform compliance status — risk engine, gateway,
    and account health combined into one snapshot for the frontend.
    """
    health = await risk_client.get_account_health()
    gateway = await risk_client.get_gateway_status()
    return {
        "status": "compliant" if not health.is_locked else "non_compliant",
        "risk_engine": "active",
        "gateway": gateway.get("status", "UNKNOWN"),
        "account_locked": health.is_locked,
        "daily_drawdown_pct": health.daily_drawdown_pct,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get(
    "/constitution",
    response_model=AppConstitution,
    summary="Get the trader's current rules and limits",
    tags=["Governance"],
)
async def get_constitution(uid: str = Depends(get_current_user)):
    const = await ConstitutionManager.load(user_id=uid)
    # MOAT PROTECTION: Strip condition_payload and created_at before sending
    # to the client. The raw AI-generated condition logic is internal IP and
    # must never leave the server. The user only needs name, description,
    # rule_type, parameter, and is_active to understand and adjust their rules.
    for rule in const.rules:
        rule.condition_payload = {}
    return const


@router.post(
    "/constitution",
    response_model=AppConstitution,
    summary="Update the trader's rules",
    tags=["Governance"],
)
@limiter.limit("3/minute")
async def update_constitution(
    request: Request, const: AppConstitution, uid: str = Depends(get_current_user)
):
    # SECURITY FIX: Never trust client-supplied server-managed fields.
    # The client can only update the rules list. Server-managed counters
    # (daily_trades_count, last_reset_date) are preserved from the existing
    # constitution to prevent users from resetting their overtrading limits.
    existing = await ConstitutionManager.load(user_id=uid)
    
    # Just update the rules list, keep counts untouched
    existing.rules = const.rules
    await ConstitutionManager.save(existing, user_id=uid)
    return existing


@router.post(
    "/account/accept-terms",
    summary="Record legal terms acceptance (compliance audit trail)",
    tags=["Account"],
)
@limiter.limit("3/minute")
async def accept_terms(request: Request, uid: str = Depends(get_current_user)):
    """
    FIX #2: Creates a provable, timestamped record in Firestore that the user
    accepted the Terms of Service. This is the legal compliance record — if a
    user ever disputes, this document proves acceptance.
    """
    from storage import storage
    import json

    body = await request.body()
    try:
        data = json.loads(body) if body else {}
    except Exception:
        data = {}

    acceptance_record = {
        "uid": uid,
        "accepted_at": data.get("accepted_at", datetime.now(timezone.utc).isoformat()),
        "tos_version": data.get("version", "1.0"),
        "ip_address": get_real_ip(request),
        "timestamp_server": datetime.now(timezone.utc).isoformat(),
    }

    await storage.set("legal_acceptances", uid, acceptance_record)
    logger.info("LEGAL: User %s accepted ToS v%s", uid, acceptance_record["tos_version"])
    return {"status": "recorded", "timestamp": acceptance_record["timestamp_server"]}


@router.get(
    "/autopilot/command-center-status",
    summary="Get comprehensive Command Center status",
    tags=["Autopilot"],
)
async def get_command_center_status(uid: str = Depends(get_current_user)):
    """
    Returns the full state needed for the new Autopilot Command Center UI:
    - Active Snipers
    - System Events
    - System Status
    - Risk Overview
    """
    from storage import storage
    
    # 1. System Status
    system_pause = await storage.get("system_state", "pause_flag")
    system_status = "PAUSED" if system_pause else "ACTIVE"
    
    # 2. Active Snipers
    snipers_dict = await storage.get_all("sniper_targets") or {}
    active_snipers = []
    for symbol, data in snipers_dict.items():
        active_snipers.append({
            "symbol": symbol,
            "direction": data.get("direction", "BUY"),
            "status": data.get("state", "ARMED"),
            "entry_target": data.get("target_price", 0.0),
            "current_price": data.get("analysis_price", 0.0), # Will update with live price in UI
            "distance_pips": 0.0 # UI calculates this
        })
        
    # 3. System Events (Last 10)
    events_dict = await storage.get_all("system_events") or {}
    events = []
    # events_dict values are expected to be lists or individual events.
    # We'll just grab the values, sort by timestamp if possible
    raw_events = list(events_dict.values())
    raw_events.sort(key=lambda x: x.get("timestamp", ""), reverse=True)
    for ev in raw_events[:20]:
        events.append(ev)

    # 4. Risk Overview
    cfg_raw = await storage.get("autopilot_configs", uid)
    if cfg_raw:
        from models import AutopilotConfig
        cfg = AutopilotConfig.model_validate(cfg_raw)
        equity = getattr(cfg, "simulated_equity", 100.0)
        drawdown = getattr(cfg, "current_drawdown_pct", 0.0)
        open_pos_count = len(cfg.open_auto_positions)
        max_pos = cfg.max_concurrent_positions
    else:
        equity = 100.0
        drawdown = 0.0
        open_pos_count = 0
        max_pos = 3

    # 5. GAP #1 FIX: Real system health indicators (Robinhood lesson)
    # Instead of mocking broker_latency_ms=120, we check actual system state
    # so the Flutter app can show honest degradation warnings.
    execution_status = "ACTIVE"
    degradation_reasons = []
    
    if system_pause:
        execution_status = "PAUSED"
        pause_data = system_pause if isinstance(system_pause, dict) else {}
        degradation_reasons.append(pause_data.get("reason", "Circuit breaker triggered"))
    
    # Check broker connectivity
    broker_connected = True
    try:
        from broker_gateway import broker_gateway as _bg
        broker_status = _bg.get_status() if hasattr(_bg, 'get_status') else {"connected": True}
        broker_connected = broker_status.get("connected", True)
    except Exception:
        broker_connected = False
        
    if not broker_connected:
        execution_status = "DEGRADED"
        degradation_reasons.append("Broker gateway disconnected")
    
    # Check consensus engine availability
    consensus_healthy = True
    try:
        from consensus_engine import engine
        consensus_healthy = engine is not None
    except Exception:
        consensus_healthy = False
        
    if not consensus_healthy:
        if execution_status == "ACTIVE":
            execution_status = "DEGRADED"
        degradation_reasons.append("Consensus engine unavailable")

    # 6. Subsystem Health (public level — no internal metrics exposed)
    from system_health import health_registry
    from state import DEMO_MODE
    health_snapshot = await health_registry.snapshot(ops_level=False)

    return {
        "is_simulated": DEMO_MODE,
        "execution_status": execution_status,
        "system_status": system_status,
        "broker_connected": broker_connected,
        "consensus_healthy": consensus_healthy,
        "degradation_reasons": degradation_reasons,
        "active_snipers": active_snipers,
        "system_events": events,
        "subsystem_health": health_snapshot,
        "risk_overview": {
            "equity": equity,
            "daily_drawdown": drawdown,
            "max_drawdown_limit": 5.0,
            "open_positions": open_pos_count,
            "max_positions": max_pos,
            "risk_per_trade_pct": 1.0
        }
    }

@router.post(
    "/broker",
    summary="Connect exchange API keys securely",
    tags=["Account"],
)
@limiter.limit("5/minute")
async def connect_broker(
    request: Request, payload: BrokerCredentialsPayload, uid: str = Depends(get_current_user)
):
    """
    Encrypts and saves the user's broker API keys to the secure Server-Side KMS Vault.
    Keys are NEVER stored in plain text.
    """
    if not payload.api_key or not payload.api_secret:
        raise HTTPException(status_code=400, detail="API key and secret required.")

    # Whitelist check: only allow known exchanges
    ALLOWED_EXCHANGES = {"binance", "bybit", "exness"}
    if payload.exchange_id.lower() not in ALLOWED_EXCHANGES:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported exchange '{payload.exchange_id}'. Allowed: {', '.join(ALLOWED_EXCHANGES)}"
        )

    encrypted_key = encryption.encrypt(payload.api_key)
    encrypted_secret = encryption.encrypt(payload.api_secret)
    
    vault_data = {
        "exchange_id": payload.exchange_id.lower(),  # Normalize to lowercase
        "encrypted_api_key": encrypted_key,
        "encrypted_api_secret": encrypted_secret,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    
    # Save the encrypted blob to the user's Firestore document
    await storage.set("broker_vaults", uid, vault_data)
    
    return {"status": "success", "message": "Keys encrypted and stored in secure vault."}


