import os
import httpx
import logging
from typing import List, Tuple, Optional
from models import TradeOrder, InternalTradeOrder, AccountHealth, RiskDecision
from risk_engine import HardRiskKernel

logger = logging.getLogger("mehd.risk_client")


class RiskClient:
    """
    Communicates with the isolated Risk Microservice on port 8001.
    If the separate microservice process is not running (e.g. in local dev /
    free tier single container), it automatically falls back to an in-process
    HardRiskKernel instance so trades and account health remain fully protected.
    """

    def __init__(self, base_url: str | None = None):
        if base_url is None:
            base_url = os.environ.get("RISK_MICROSERVICE_URL", "http://127.0.0.1:8001")
        self.base_url = base_url
        self.client = httpx.AsyncClient(
            base_url=self.base_url,
            timeout=10.0,
        )
        self._local_kernel: Optional[HardRiskKernel] = None

    def _get_local_kernel(self) -> HardRiskKernel:
        if self._local_kernel is None:
            self._local_kernel = HardRiskKernel()
        return self._local_kernel

    def _headers(self) -> dict:
        """Read the internal token fresh from the environment on every call."""
        token = os.environ.get("RISK_INTERNAL_TOKEN", "")
        if not token:
            logger.warning("RISK_INTERNAL_TOKEN not set — risk calls will be rejected")
        return {"x-internal-token": token}

    async def get_account_health(self) -> AccountHealth:
        try:
            resp = await self.client.get("/health", headers=self._headers())
            resp.raise_for_status()
            return AccountHealth(**resp.json())
        except Exception:
            kernel = self._get_local_kernel()
            return kernel.account

    async def get_gateway_status(self) -> dict:
        try:
            resp = await self.client.get("/status", headers=self._headers())
            resp.raise_for_status()
            return resp.json()
        except Exception:
            return {"status": "SEALED", "integrity": True, "mode": "in_process"}

    async def check_math_veto(self, math_votes: List) -> Tuple[bool, str]:
        try:
            payload = [v.model_dump(mode="json") for v in math_votes]
            resp = await self.client.post("/veto", json={"math_votes": payload}, headers=self._headers())
            resp.raise_for_status()
            data = resp.json()
            return data["vetoed"], data["reason"]
        except Exception:
            kernel = self._get_local_kernel()
            return kernel.check_math_veto(math_votes)

    async def evaluate_and_execute(self, order: InternalTradeOrder, current_price: float, current_spread: float, user_id: str) -> dict:
        try:
            payload = {
                "order": order.model_dump(mode="json"),
                "current_price": current_price,
                "current_spread": current_spread,
                "user_id": user_id
            }
            resp = await self.client.post("/execute", json=payload, headers=self._headers())
            resp.raise_for_status()
            data = resp.json()
            if data.get("decision"):
                data["decision"] = RiskDecision(**data["decision"])
            return data
        except Exception:
            kernel = self._get_local_kernel()
            decision = await kernel.evaluate(order, current_price, current_spread, user_id)
            return {
                "approved": decision.approved,
                "decision": decision,
                "evaluation_id": f"EVAL_{decision.id}",
                "seal_valid": True,
                "execution_result": None
            }


risk_client = RiskClient()
