import os
import httpx
from models import MarketSnapshot, AIVote
from consensus.helpers import _get_vault_role, _build_system_prompt, _build_user_message, _parse_llm_json, _call_openrouter

async def _call_gemini(symbol: str, snapshot: MarketSnapshot, client: httpx.AsyncClient) -> AIVote:
    """Google Gemini — Sentiment (direct or via OpenRouter)"""
    _title, _desc = _get_vault_role("pulse_multimedia", "Multimedia Analyst", "Watches live streams, earnings calls, YouTube financial content")
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        if os.getenv("OPENROUTER_API_KEY"):
            return await _call_openrouter("google/gemini-2.0-flash-001", _title, _desc, symbol, snapshot, client, "gemini-1.5-flash")
        raise ValueError("Missing GEMINI_API_KEY or OPENROUTER_API_KEY")

    sys_prompt = _build_system_prompt(_title, _desc)
    msg = _build_user_message(symbol, snapshot)

    resp = await client.post(
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent",
        headers={"x-goog-api-key": api_key, "Content-Type": "application/json"},
        json={
            "systemInstruction": {"parts": [{"text": sys_prompt}]},
            "contents": [{"parts": [{"text": msg}]}]
        },
        timeout=25.0
    )
    resp.raise_for_status()
    text = resp.json()["candidates"][0]["content"]["parts"][0]["text"]
    return _parse_llm_json(text, "gemini-1.5-flash", snapshot.id)
