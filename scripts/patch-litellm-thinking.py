#!/usr/bin/env python3
# =============================================================================
# patch-litellm-thinking.py — FIX idempotente (mesmo do stack local, mas com
# caminho do litellm resolvido dinamicamente — funciona em qualquer python).
#
# BUG: Quando um request Anthropic /v1/messages chega com
#   thinking: {"type": "enabled"}
# para um modelo OpenAI-compatible, o litellm roteia a chamada para a
# **OpenAI Responses API** (POST /v1/responses) prefixando o model com
# "responses/". Os backends free do ai-hub (NIM/Gemini/Mistral via chat/
# completions) NÃO têm /v1/responses → 404 → erro repassado ao cliente.
#
# FIX: o flag LITELLM_USE_CHAT_COMPLETIONS_URL_FOR_ANTHROPIC_MESSAGES=true
# (exportado no bin/up) é o controle oficial "mensagens Anthropic →
# chat/completions". Este patch faz o flag vencer ANTES de qualquer consulta
# ao registry.
#
# Aplicado pelo bin/up (idempotente — não reaplica se o marcador já existe).
# No ai-hub o thinking fica OFF por padrão (ENABLE_MODEL_THINKING=false), então
# o patch é rede de segurança para quando for ligado.
# =============================================================================

import pathlib
import sys
import sysconfig

MARKER = "PATCH-litellm-thinking-aihub"

FILE = (
    pathlib.Path(sysconfig.get_paths()["purelib"])
    / "litellm"
    / "llms/anthropic/experimental_pass_through/adapters/handler.py"
)

OLD = """        model = completion_kwargs.get("model")
        try:
            model_info = get_model_info(model=cast(str, model), custom_llm_provider=custom_llm_provider)
            if model_info and model_info.get("supports_reasoning") is False:
                # Model doesn't support reasoning/responses API, don't route
                return
        except Exception:
            pass
"""

NEW = """        model = completion_kwargs.get("model")
        # PATCH-litellm-thinking-aihub: o flag abaixo já é o controle oficial
        # para "traduzir mensagens Anthropic via chat/completions em vez da
        # Responses API". O roteamento de thinking re-prefixava o model com
        # "responses/" e sobrepunha o flag para backends que não têm
        # /v1/responses (NIM/Gemini/Mistral via chat/completions).
        # Aqui o flag vence ANTES de qualquer consulta ao registry.
        if litellm.use_chat_completions_url_for_anthropic_messages:
            return
""".replace("__MARKER__", MARKER)


def main() -> int:
    if not FILE.exists():
        print(f"ERRO: arquivo não encontrado: {FILE}", file=sys.stderr)
        return 1
    src = FILE.read_text()
    if MARKER in src:
        print("patch já aplicado — nada a fazer.")
        return 0
    if OLD not in src:
        print("ERRO: trecho original não encontrado — versão do litellm mudou?", file=sys.stderr)
        print("   (não crítico: thinking está OFF por padrão no ai-hub)", file=sys.stderr)
        return 1
    FILE.write_text(src.replace(OLD, NEW))
    print(f"patch aplicado em {FILE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
