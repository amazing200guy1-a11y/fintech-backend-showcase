import os
import httpx
from models import MarketSnapshot, AIVote
from consensus.helpers import _get_vault_role, _build_system_prompt, _build_user_message, _parse_llm_json, _call_openrouter

async def _call_grok(symbol: str, snapshot: MarketSnapshot, client: httpx.AsyncClient) -> AIVote:
    """xAI Grok / Cipher — Street Intelligence & News (direct or via OpenRouter)"""
    _title, _desc = _get_vault_role("pulse_x", "Street Intelligence Analyst", "Breaking news, order book depth, and social sentiment")
    api_key = os.getenv("XAI_API_KEY") or os.getenv("GROK_API_KEY") or os.getenv("GROQ_API_KEY")
    if not api_key:
        if os.getenv("OPENROUTER_API_KEY"):
            return await _call_openrouter("x-ai/grok-2-1212", _title, _desc, symbol, snapshot, client, "grok-beta")
        raise ValueError("Missing XAI_API_KEY, GROK_API_KEY, or OPENROUTER_API_KEY")

    sys_prompt = _build_system_prompt(_title, _desc)
    msg = _build_user_message(symbol, snapshot)

    # If xAI official key is used
    if os.getenv("XAI_API_KEY") or os.getenv("GROK_API_KEY"):
        direct_key = os.getenv("XAI_API_KEY") or os.getenv("GROK_API_KEY")
        resp = await client.post(
            "https://api.x.ai/v1/chat/completions",
            headers={"Authorization": f"Bearer {direct_key}"},
            json={
                "model": "grok-2-latest",
                "messages": [
                    {"role": "system", "content": sys_prompt},
                    {"role": "user", "content": msg}
                ],
                "temperature": 0.2
            }
        )
    else:
        # Groq LPU fast fallback
        resp = await client.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={"Authorization": f"Bearer {api_key}"},
            json={
                "model": "llama-3.3-70b-versatile",
                "messages": [
                    {"role": "system", "content": sys_prompt},
                    {"role": "user", "content": msg}
                ],
                "temperature": 0.2
            }
        )
    resp.raise_for_status()
    text = resp.json()["choices"][0]["message"]["content"]
    return _parse_llm_json(text, "grok-beta", snapshot.id)
