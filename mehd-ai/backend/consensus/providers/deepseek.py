import os
import httpx
from models import MarketSnapshot, AIVote
from consensus.helpers import _get_vault_role, _build_system_prompt, _build_user_message, _parse_llm_json, _call_openrouter

async def _call_deepseek(symbol: str, snapshot: MarketSnapshot, client: httpx.AsyncClient) -> AIVote:
    """DeepSeek V3 / R1 — Math / Quants (direct or via OpenRouter)"""
    _title, _desc = _get_vault_role("math_backtest", "Backtesting Specialist", "Runs historical simulations instantly")
    api_key = os.getenv("DEEPSEEK_API_KEY")
    if not api_key:
        if os.getenv("OPENROUTER_API_KEY"):
            return await _call_openrouter("deepseek/deepseek-r1", _title, _desc, symbol, snapshot, client, "deepseek-chat")
        raise ValueError("Missing DEEPSEEK_API_KEY or OPENROUTER_API_KEY")
        
    sys_prompt = _build_system_prompt(_title, _desc)
    msg = _build_user_message(symbol, snapshot)
    
    resp = await client.post(
        "https://api.deepseek.com/chat/completions",
        headers={"Authorization": f"Bearer {api_key}"},
        json={
            "model": "deepseek-chat",
            "response_format": {"type": "json_object"},
            "messages": [
                {"role": "system", "content": sys_prompt},
                {"role": "user", "content": msg}
            ],
            "temperature": 0.1
        }
    )
    resp.raise_for_status()
    text = resp.json()["choices"][0]["message"]["content"]
    return _parse_llm_json(text, "deepseek-chat", snapshot.id)
