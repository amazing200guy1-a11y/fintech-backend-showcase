"""
Mehd AI — Moonshot AI (Kimi) Provider Integration
===================================================
Powers SENTINEL (Layer 4 Anti-Hallucination & Paradox Reviewer).
API Endpoint: https://api.moonshot.cn/v1
"""

from __future__ import annotations

import logging
import os
import httpx
from typing import Optional

logger = logging.getLogger("mehd.consensus.providers.moonshot")

MOONSHOT_API_URL = "https://api.moonshot.cn/v1/chat/completions"

async def call_kimi(system_prompt: str, user_message: str) -> Optional[str]:
    """
    Calls Moonshot AI's Kimi API (kimi-latest).
    Returns raw JSON text string or None on failure.
    """
    api_key = os.getenv("MOONSHOT_API_KEY", "").strip()
    if not api_key:
        logger.debug("MOONSHOT_API_KEY not configured — skipping Kimi (SENTINEL)")
        return None

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }

    payload = {
        "model": "kimi-latest",
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_message},
        ],
        "temperature": 0.2,
        "max_tokens": 1000,
    }

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(MOONSHOT_API_URL, headers=headers, json=payload)
            if resp.status_code == 200:
                data = resp.json()
                return data["choices"][0]["message"]["content"]
            else:
                logger.warning("Moonshot API HTTP error %d: %s", resp.status_code, resp.text[:200])
                return None
    except Exception as e:
        logger.error("Moonshot API call failed for Kimi: %s", e)
        return None
