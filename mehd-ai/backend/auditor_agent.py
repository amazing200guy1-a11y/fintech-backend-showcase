"""
Mehd AI — Auditor Post-Mortem Agent
====================================
The Auditor reviews completed trades after exit, categorizes Mistake DNA
(FOMO, Over-leveraged, Impatience, etc.), and optionally proposes new
Constitution rules.
"""

import os
import json
import logging
from typing import Optional
import httpx
from models import Direction

logger = logging.getLogger("mehd.auditor_agent")


class AuditorAgent:
    """
    The Auditor reviews completed trades and assigns Mistake DNA.
    It uses Claude for post-mortem risk analysis.
    """

    async def perform_audit(
        self,
        trade_id: str,
        symbol: str,
        direction: Direction,
        entry_price: float,
        exit_price: float,
        pnl: float,
        user_notes: Optional[str] = None
    ) -> dict:
        """
        The Auditor reviews completed trades and assigns Mistake DNA.
        """
        prompt = f"""
        You are The Auditor, the ruthless post-mortem analyst for a proprietary trading firm.
        A trader just closed a position. Your job is to analyze the outcome without emotion.
        
        Trade Details:
        - Symbol: {symbol}
        - Direction: {direction.value}
        - Entry Price: {entry_price}
        - Exit Price: {exit_price}
        - PnL: ${pnl:.2f}
        - Trader Notes: {user_notes or "None"}
        
        Categorize the Mistake DNA into exactly ONE of these categories:
        [FOMO, Revenge Trading, Over-leveraged, Impatience, Systematic Loss, Undefined]
        If it was a winning trade that followed rules, categorize as "Systematic Execution".
        
        Provide a brutal 2-sentence analysis.
        If the mistake is severe, propose a Constitution Rule to prevent it.
        
        Respond ONLY in raw JSON format matching this structure:
        {{
            "mistake_dna": "String",
            "analysis": "String",
            "suggested_rule": {{
                "name": "String",
                "description": "String",
                "rule_type": "max_daily_trades | min_consensus | forbidden_hours",
                "parameter": Float
            }} // Or null if no rule is needed
        }}
        """

        payload = {
            "model": "claude-3-opus-20240229",
            "max_tokens": 300,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.0,
        }

        api_key = os.getenv("ANTHROPIC_API_KEY")
        if not api_key:
            logger.warning("No Anthropic API key, falling back to mock Auditor.")
            return self._mock_audit(pnl)

        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                response = await client.post(
                    "https://api.anthropic.com/v1/messages",
                    headers={
                        "x-api-key": api_key,
                        "anthropic-version": "2023-06-01",
                        "content-type": "application/json"
                    },
                    json=payload
                )
                if response.status_code == 200:
                    data = response.json()
                    raw_text = data["content"][0]["text"]
                    if "{" in raw_text and "}" in raw_text:
                        start_idx = raw_text.find("{")
                        end_idx = raw_text.rfind("}") + 1
                        json_str = raw_text[start_idx:end_idx]
                        parsed_res = json.loads(json_str)
                        self._save_audit_to_cloud(trade_id, symbol, parsed_res)
                        return parsed_res
            except Exception as e:
                logger.error("[AUDITOR] Claude failed: %s", e)

        mock_res = self._mock_audit(pnl)
        self._save_audit_to_cloud(trade_id, symbol, mock_res)
        return mock_res

    def _save_audit_to_cloud(self, trade_id: str, symbol: str, audit_data: dict):
        """Safely pushes the Auditor's findings to the Sovereign Cloud."""
        try:
            from sovereign_intelligence import sovereign_db
            if sovereign_db.use_cloud and sovereign_db._db:
                from firebase_admin import firestore
                doc_ref = sovereign_db._db.collection('auditor_ledger').document(trade_id)
                data = {
                    "symbol": symbol,
                    "timestamp": firestore.SERVER_TIMESTAMP,
                    "mistake_dna": audit_data.get("mistake_dna", "Unknown"),
                    "analysis": audit_data.get("analysis", ""),
                    "suggested_rule": audit_data.get("suggested_rule")
                }
                doc_ref.set(data)
                logger.info("[AUDITOR] Mistake DNA pushed to Global Ledger for %s", symbol)
        except Exception as e:
            logger.error("[AUDITOR] Failed to push ledger to cloud: %s", e)

    def _mock_audit(self, pnl: float) -> dict:
        if pnl < 0:
            return {
                "mistake_dna": "Impatience",
                "analysis": "You entered the trade before the full consensus was formed, resulting in a premature entry and subsequent loss.",
                "suggested_rule": {
                    "name": "Consensus Patience",
                    "description": "Never trade below 85% consensus.",
                    "rule_type": "min_consensus",
                    "parameter": 85.0
                }
            }
        else:
            return {
                "mistake_dna": "Systematic Execution",
                "analysis": "The trade followed the parameters laid out by the Den. Capital compounding successful.",
                "suggested_rule": None
            }


auditor_agent = AuditorAgent()
