import os
import httpx
from models import MarketSnapshot, AIVote
from consensus.helpers import _get_vault_role, _build_system_prompt, _build_user_message, _parse_llm_json

async def _call_claude(symbol: str, snapshot: MarketSnapshot, client: httpx.AsyncClient) -> AIVote:
    """Anthropic Claude Opus — Strategy"""
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        raise ValueError("Missing ANTHROPIC_API_KEY")
        
    _title, _desc = _get_vault_role("strategist_risk", "Risk and Ethics Auditor", "Finds problems in the Strategy Officer's plan")
    sys_prompt = _build_system_prompt(_title, _desc)
    msg = _build_user_message(symbol, snapshot)
    
    resp = await client.post(
        "https://api.anthropic.com/v1/messages",
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01"
        },
        json={
            "model": "claude-3-5-sonnet-20240620",
            "max_tokens": 300,
            "system": sys_prompt,
            "messages": [{"role": "user", "content": msg}],
            "temperature": 0.1
        }
    )
    resp.raise_for_status()
    text = resp.json()["content"][0]["text"]
    return _parse_llm_json(text, "claude-3-5-sonnet-20240620", snapshot.id)
