from consensus.providers.grok import _call_grok
from consensus.providers.perplexity import _call_perplexity
from consensus.providers.gemini import _call_gemini
from consensus.providers.claude import _call_claude
from consensus.providers.gpt4 import _call_gpt4
from consensus.providers.llama import _call_llama
from consensus.providers.deepseek import _call_deepseek
from consensus.providers.openai_o3 import _call_openai_o3
from consensus.providers.codestral import _call_codestral
from consensus.providers.moonshot import call_kimi

MODEL_FUNCTIONS = {
    "grok": _call_grok,
    "perplexity": _call_perplexity,
    "gemini": _call_gemini,
    "claude": _call_claude,
    "gpt-4": _call_gpt4,
    "llama": _call_llama,
    "deepseek": _call_deepseek,
    "openai-o3": _call_openai_o3,
    "codestral": _call_codestral,
    "kimi": call_kimi,
    "kimi-latest": call_kimi,
}
