import os
import math
import time
import random
import httpx
import json
import logging
from datetime import datetime
from typing import Optional, Dict, Any, List
from pydantic import BaseModel
from uuid import UUID

logger = logging.getLogger("mehd.api_service")

class AgentVote(BaseModel):
    agent: str
    direction: str
    confidence: float
    reasoning: str
    is_simulated: bool = False
    data_source: str = "live"

class PriceData(BaseModel):
    symbol: str
    price: float
    bid: float
    ask: float
    timestamp: str
    is_simulated: bool = False
    data_source: str = "live"

class ApiService:
    DEMO_MODE = os.getenv('DEMO_MODE', 'true').lower() in ('true', '1', 'yes')

    def __init__(self):
        # Keys would be loaded from env
        self.groq_key = os.getenv('GROQ_API_KEY')
        self.gemini_key = os.getenv('GEMINI_API_KEY')
        self.mistral_key = os.getenv('MISTRAL_API_KEY')
        self.twelve_data_key = os.getenv('TWELVE_DATA_KEY')

    async def call_groq(self, prompt: str) -> AgentVote:
        if self.DEMO_MODE:
            return self._mock_vote('DON', prompt)
        
        if not self.groq_key:
            return self._mock_vote('DON', prompt) # Fallback if key missing in non-demo? Or error?
            
        async with httpx.AsyncClient() as client:
            try:
                headers = {'Authorization': f'Bearer {self.groq_key}'}
                response = await client.post(
                    'https://api.groq.com/openai/v1/chat/completions',
                    headers=headers,
                    json={
                        'model': 'llama3-groq-70b-8192-tool-use-preview',
                        'messages': [{'role': 'user', 'content': prompt}]
                    },
                    timeout=10.0
                )
                response.raise_for_status()
                return self._parse_vote('DON', response.json())
            except Exception as e:
                logger.error("Groq API error: %s", e)
                return self._mock_vote('DON', prompt)

    async def call_gemini(self, prompt: str) -> AgentVote:
        if self.DEMO_MODE:
            return self._mock_vote('ORACLE', prompt)
        
        if not self.gemini_key:
            return self._mock_vote('ORACLE', prompt)

        async with httpx.AsyncClient() as client:
            try:
                response = await client.post(
                    'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent',
                    headers={'x-goog-api-key': self.gemini_key},
                    json={'contents': [{'parts': [{'text': prompt}]}]},
                    timeout=10.0
                )
                response.raise_for_status()
                return self._parse_vote('ORACLE', response.json())
            except Exception as e:
                logger.error("Gemini API error: %s", e)
                return self._mock_vote('ORACLE', prompt)

    async def call_mistral(self, prompt: str) -> AgentVote:
        if self.DEMO_MODE:
            return self._mock_vote('FORGE', prompt)
        
        if not self.mistral_key:
            return self._mock_vote('FORGE', prompt)

        async with httpx.AsyncClient() as client:
            try:
                response = await client.post(
                    'https://api.mistral.ai/v1/chat/completions',
                    headers={'Authorization': f'Bearer {self.mistral_key}'},
                    json={
                        'model': 'codestral-latest',
                        'messages': [{'role': 'user', 'content': prompt}]
                    },
                    timeout=10.0
                )
                response.raise_for_status()
                return self._parse_vote('FORGE', response.json())
            except Exception as e:
                logger.error("Mistral API error: %s", e)
                return self._mock_vote('FORGE', prompt)

    async def get_price(self, symbol: str) -> PriceData:
        if self.DEMO_MODE:
            return self._mock_price(symbol)
        
        if not self.twelve_data_key:
            return self._mock_price(symbol)

        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(
                    'https://api.twelvedata.com/price',
                    params={'symbol': symbol, 'apikey': self.twelve_data_key},
                    timeout=5.0
                )
                response.raise_for_status()
                data = response.json()
                price = float(data.get('price', 0.0))
                return PriceData(
                    symbol=symbol,
                    price=price,
                    bid=price - 0.0001,
                    ask=price + 0.0001,
                    timestamp=datetime.now().isoformat()
                )
            except Exception as e:
                logger.error("Price API error: %s", e)
                return self._mock_price(symbol)

    def _mock_vote(self, agent: str, prompt: str) -> AgentVote:
        directions = ['BUY', 'BUY', 'BUY', 'SELL', 'HOLD']
        return AgentVote(
            agent=agent,
            direction=random.choice(directions),
            confidence=round(random.uniform(62, 94), 1),
            reasoning=f'{agent} institutional analysis: market conditions show structural confluence.',
            is_simulated=True,
            data_source="mock"
        )

    def _mock_price(self, symbol: str) -> PriceData:
        # Institutional jitter — simulated high-frequency activity
        base_prices = {
            'EUR/USD': 1.08420,
            'GBP/USD': 1.26340,
            'XAU/USD': 2318.50,
            'USD/JPY': 149.820,
            'BTC/USD': 64210.00,
        }
        base = base_prices.get(symbol, 1.0)
        
        # Add micro-volatility (0.1 - 0.5 pips)
        jitter = random.uniform(-0.00005, 0.00005)
        # Add trend bias based on time
        bias = math.sin(time.time() / 60) * 0.0002 
        
        price = round(base + jitter + bias, 5 if 'JPY' not in symbol else 3)
        spread = random.uniform(0.00005, 0.00009)
        
        return PriceData(
            symbol=symbol,
            price=price,
            bid=round(price - spread/2, 5),
            ask=round(price + spread/2, 5),
            timestamp=datetime.now().isoformat(),
            is_simulated=True,
            data_source="mock"
        )

    def _parse_vote(self, agent: str, response_json: Dict[str, Any]) -> AgentVote:
        try:
            # Parse the LLM response content
            content = response_json['choices'][0]['message']['content']
            # Attempt to parse structured JSON from the response
            try:
                parsed = json.loads(content)
                raw_direction = str(parsed.get('direction', 'HOLD')).upper().strip()
                # SECURITY: Validate direction against allowed values
                if raw_direction not in ('BUY', 'SELL', 'HOLD'):
                    raw_direction = 'HOLD'
                confidence = max(0.0, min(100.0, float(parsed.get('confidence', 50.0))))
                reasoning = str(parsed.get('reasoning', content[:100]))[:300]
            except (json.JSONDecodeError, KeyError, TypeError):
                # Fallback: try to extract direction from plain text
                content_upper = content.upper()
                if 'BUY' in content_upper:
                    raw_direction = 'BUY'
                elif 'SELL' in content_upper:
                    raw_direction = 'SELL'
                else:
                    raw_direction = 'HOLD'
                confidence = 50.0
                reasoning = content[:100]
            
            return AgentVote(
                agent=agent,
                direction=raw_direction,
                confidence=confidence,
                reasoning=reasoning
            )
        except Exception:
            return self._mock_vote(agent, "Parse error")


