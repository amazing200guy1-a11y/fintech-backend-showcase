import os
import httpx
from models import MarketSnapshot, AIVote
from consensus.helpers import _get_vault_role, _build_system_prompt, _build_user_message, _parse_llm_json, _call_openrouter

async def _call_llama(symbol: str, snapshot: MarketSnapshot, client: httpx.AsyncClient) -> AIVote:
    """Llama 3.3 / Guardian — Capital Protection (direct via Groq or via OpenRouter)"""
    _title, _desc = _get_vault_role("sovereign_vault", "Private Data Vault & Risk Guardian", "Enforces hard risk rules and capital protection protocols")
    api_key = os.getenv("GROQ_API_KEY") or os.getenv("TOGETHER_API_KEY")
    if not api_key:
        if os.getenv("OPENROUTER_API_KEY"):
            return await _call_openrouter("meta-llama/llama-3.3-70b-instruct", _title, _desc, symbol, snapshot, client, "llama-3.1-70b")
        raise ValueError("Missing GROQ_API_KEY, TOGETHER_API_KEY, or OPENROUTER_API_KEY")
        
    sys_prompt = _build_system_prompt(_title, _desc)
    msg = _build_user_message(symbol, snapshot)
    
    resp = await client.post(
        "https://api.groq.com/openai/v1/chat/completions",
        headers={"Authorization": f"Bearer {api_key}"},
        json={
            "model": "llama-3.3-70b-versatile",
            "messages": [
                {"role": "system", "content": sys_prompt},
                {"role": "user", "content": msg}
            ],
            "temperature": 0.1
        }
    )
    resp.raise_for_status()
    text = resp.json()["choices"][0]["message"]["content"]
    return _parse_llm_json(text, "llama-3.1-70b", snapshot.id)
