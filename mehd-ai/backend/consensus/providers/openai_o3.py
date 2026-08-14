import os
import httpx
from models import MarketSnapshot, AIVote
from consensus.helpers import _get_vault_role, _build_system_prompt, _build_user_message, _parse_llm_json

async def _call_openai_o3(symbol: str, snapshot: MarketSnapshot, client: httpx.AsyncClient) -> AIVote:
    """OpenAI o3-mini — Math / Reasoning"""
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise ValueError("Missing OPENAI_API_KEY (for o3)")
        
    _title, _desc = _get_vault_role("math_quant", "Quantitative Calculator", "Kelly Criterion, position sizing, slippage prediction")
    sys_prompt = _build_system_prompt(_title, _desc)
    msg = _build_user_message(symbol, snapshot)
    
    resp = await client.post(
        "https://api.openai.com/v1/chat/completions",
        headers={"Authorization": f"Bearer {api_key}"},
        json={
            "model": "o3-mini",
            # o3 doesn't support system prompts the same way, put it all in developer/user wrapper
            "messages": [
                {"role": "system", "content": sys_prompt},
                {"role": "user", "content": msg}
            ]
        }
    )
    resp.raise_for_status()
    text = resp.json()["choices"][0]["message"]["content"]
    return _parse_llm_json(text, "o3-mini", snapshot.id)
