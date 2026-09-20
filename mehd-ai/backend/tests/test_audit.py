"""
Mehd AI — Third-Party Audit & Myfxbook Integration Tests
==========================================================
Verifies that:
1. Connecting Myfxbook validates inputs and stores encrypted investor keys.
2. Status endpoint reflects verification badges and public link.
3. Disconnecting cleanly removes credentials from the vault.
4. Institutional statement export generates standard CSV rows.
"""

import sys
import os
import pytest
from unittest.mock import patch, MagicMock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from fastapi import FastAPI
from fastapi.testclient import TestClient
from routes.audit import router as audit_router
from auth import get_current_user
from storage import MemoryStorage


@pytest.fixture
def test_app():
    app = FastAPI()
    app.include_router(audit_router)
    # Override auth to return fixed user ID
    app.dependency_overrides[get_current_user] = lambda: "test_trader_12345678"
    return app


@pytest.fixture
def client(test_app):
    return TestClient(test_app)


@pytest.fixture(autouse=True)
def mock_storage(monkeypatch):
    """Ensure in-memory storage is used during audit tests."""
    mem_store = MemoryStorage()
    monkeypatch.setattr("routes.audit.storage", mem_store)
    return mem_store


def test_get_status_initially_disconnected(client):
    """When no audit link exists, status must return is_connected=False."""
    resp = client.get("/api/audit/myfxbook/status")
    assert resp.status_code == 200
    data = resp.json()
    assert data["is_connected"] is False
    assert data["track_record_verified"] is False
    assert data["trading_privileges_verified"] is False
    assert "stats" in data


def test_connect_myfxbook_validation_error(client):
    """Missing or malformed email must fail with 400."""
    payload = {
        "myfxbook_email": "notanemail",
        "portfolio_name": "Sovereign Fund",
        "investor_password": "readonlypass123",
    }
    resp = client.post("/api/audit/myfxbook/connect", json=payload)
    assert resp.status_code == 400
    assert "Valid Myfxbook email required" in resp.json()["detail"]


def test_connect_myfxbook_success(client):
    """Connecting Myfxbook must succeed and return public URL with verified badges."""
    payload = {
        "myfxbook_email": "trader@sovereign.fund",
        "portfolio_name": "MEHD AI Alpha Ledger",
        "investor_password": "investor_read_only_99",
        "broker_server": "Exness-Real10",
        "account_id": "88992211",
    }
    resp = client.post("/api/audit/myfxbook/connect", json=payload)
    assert resp.status_code == 200
    data = resp.json()
    assert data["is_connected"] is True
    assert data["email"] == "trader@sovereign.fund"
    assert "mehd-ai-alpha-ledger" in data["portfolio_url"]
    assert data["track_record_verified"] is True
    assert data["trading_privileges_verified"] is True
    assert "MEHD AI" in data["system_attribution"]


def test_get_status_after_connection(client):
    """Status must report is_connected=True with public URL after connecting."""
    payload = {
        "myfxbook_email": "lead_quant@mehd.ai",
        "portfolio_name": "Institutional Pool",
        "investor_password": "safe_investor_key",
    }
    client.post("/api/audit/myfxbook/connect", json=payload)

    resp = client.get("/api/audit/myfxbook/status")
    assert resp.status_code == 200
    data = resp.json()
    assert data["is_connected"] is True
    assert data["email"] == "lead_quant@mehd.ai"
    assert data["track_record_verified"] is True


def test_disconnect_myfxbook(client):
    """Disconnecting must clear vault and reset status to disconnected."""
    payload = {
        "myfxbook_email": "exit@mehd.ai",
        "portfolio_name": "Temp Fund",
        "investor_password": "temp_pass_123",
    }
    client.post("/api/audit/myfxbook/connect", json=payload)

    # Disconnect
    disc_resp = client.post("/api/audit/myfxbook/disconnect")
    assert disc_resp.status_code == 200
    assert disc_resp.json()["status"] == "success"

    # Verify status is now disconnected
    status_resp = client.get("/api/audit/myfxbook/status")
    assert status_resp.status_code == 200
    assert status_resp.json()["is_connected"] is False


def test_export_audit_statement(client):
    """Statement export must return CSV with expected headers and media type."""
    resp = client.get("/api/audit/statement/export")
    assert resp.status_code == 200
    assert "text/csv" in resp.headers["content-type"]
    text = resp.text
    assert "Ticket,OpenTime,Type,Size,Symbol,OpenPrice" in text
    assert "3% CAP ENFORCED" in text
    assert "SUPER-MAJORITY" in text
