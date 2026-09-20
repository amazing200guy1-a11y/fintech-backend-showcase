import os
import httpx
from models import MarketSnapshot, AIVote
from consensus.helpers import _get_vault_role, _build_system_prompt, _build_user_message, _parse_llm_json, _call_openrouter

async def _call_openai_o3(symbol: str, snapshot: MarketSnapshot, client: httpx.AsyncClient) -> AIVote:
    """OpenAI o3-mini / Atlas — Quantitative Reasoning (direct or via OpenRouter)"""
    _title, _desc = _get_vault_role("math_quant", "Quantitative Calculator", "Kelly Criterion, position sizing, slippage prediction")
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        if os.getenv("OPENROUTER_API_KEY"):
            return await _call_openrouter("openai/o3-mini", _title, _desc, symbol, snapshot, client, "o3-mini")
        raise ValueError("Missing OPENAI_API_KEY or OPENROUTER_API_KEY")
        
    sys_prompt = _build_system_prompt(_title, _desc)
    msg = _build_user_message(symbol, snapshot)
    
    resp = await client.post(
        "https://api.openai.com/v1/chat/completions",
        headers={"Authorization": f"Bearer {api_key}"},
        json={
            "model": "o3-mini",
            "messages": [
                {"role": "system", "content": sys_prompt},
                {"role": "user", "content": msg}
            ]
        }
    )
    resp.raise_for_status()
    text = resp.json()["choices"][0]["message"]["content"]
    return _parse_llm_json(text, "o3-mini", snapshot.id)
