"""
Mehd AI — Moonshot AI (Kimi) Provider Integration
===================================================
Powers SENTINEL (Layer 4 Anti-Hallucination & Paradox Reviewer).
API Endpoint: https://api.moonshot.cn/v1
OpenRouter fallback: moonshot/moonshot-v1-8k
"""

from __future__ import annotations

import logging
import os
import httpx
from typing import Optional

logger = logging.getLogger("mehd.consensus.providers.moonshot")

MOONSHOT_API_URL = "https://api.moonshot.cn/v1/chat/completions"
OPENROUTER_API_URL = "https://openrouter.ai/api/v1/chat/completions"

async def call_kimi(system_prompt: str, user_message: str) -> Optional[str]:
    """
    Calls Moonshot AI's Kimi API (kimi-latest) or falls back to OpenRouter.
    Returns raw JSON text string or None on failure.
    """
    api_key = os.getenv("MOONSHOT_API_KEY", "").strip()
    openrouter_key = os.getenv("OPENROUTER_API_KEY", "").strip()

    if not api_key and not openrouter_key:
        logger.debug("No MOONSHOT_API_KEY or OPENROUTER_API_KEY — skipping Kimi (SENTINEL)")
        return None

    # Prefer direct Moonshot key; fall back to OpenRouter
    if api_key:
        url = MOONSHOT_API_URL
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }
        model = "kimi-latest"
    else:
        url = OPENROUTER_API_URL
        headers = {
            "Authorization": f"Bearer {openrouter_key}",
            "HTTP-Referer": "https://mehd.ai",
            "X-Title": "MEHD AI Institutional Quant Swarm",
            "Content-Type": "application/json",
        }
        model = "moonshot/moonshot-v1-8k"

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_message},
        ],
        "temperature": 0.2,
        "max_tokens": 1000,
    }

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(url, headers=headers, json=payload)
            if resp.status_code == 200:
                data = resp.json()
                return data["choices"][0]["message"]["content"]
            else:
                logger.warning("Moonshot/OpenRouter API HTTP error %d: %s", resp.status_code, resp.text[:200])
                return None
    except Exception as e:
        logger.error("Moonshot API call failed for Kimi: %s", e)
        return None
