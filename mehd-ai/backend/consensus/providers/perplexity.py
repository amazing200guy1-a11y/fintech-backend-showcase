import os
import httpx
from models import MarketSnapshot, AIVote
from consensus.helpers import _get_vault_role, _build_system_prompt, _build_user_message, _parse_llm_json, _call_openrouter

async def _call_perplexity(symbol: str, snapshot: MarketSnapshot, client: httpx.AsyncClient) -> AIVote:
    """Perplexity Sonar — Real-time web sentiment & verification (direct or via OpenRouter)"""
    _title, _desc = _get_vault_role("pulse_verify", "Verification Agent", "Cross-references and confirms rumors against official sources")
    api_key = os.getenv("PERPLEXITY_API_KEY")
    if not api_key:
        if os.getenv("OPENROUTER_API_KEY"):
            return await _call_openrouter("perplexity/sonar-pro", _title, _desc, symbol, snapshot, client, "sonar-small-online")
        raise ValueError("Missing PERPLEXITY_API_KEY or OPENROUTER_API_KEY")
        
    sys_prompt = _build_system_prompt(_title, _desc)
    msg = _build_user_message(symbol, snapshot)
    
    resp = await client.post(
        "https://api.perplexity.ai/chat/completions",
        headers={"Authorization": f"Bearer {api_key}"},
        json={
            "model": "sonar-pro",
            "messages": [
                {"role": "system", "content": sys_prompt},
                {"role": "user", "content": msg}
            ],
            "temperature": 0.2
        }
    )
    resp.raise_for_status()
    text = resp.json()["choices"][0]["message"]["content"]
    return _parse_llm_json(text, "sonar-small-online", snapshot.id)
