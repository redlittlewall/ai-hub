# ai-hub — infraestrutura gratuita de LLMs para o free-claude-code

Hub local que roda o **free-claude-code** com foco em **APIs de LLM gratuitas**
(free tiers oficiais, sem modelo local e sem API paga). Um comando sobe tudo, de
qualquer terminal.

**Objetivo:** entregar qualidade ≥ `deepseek-v4-flash` a custo zero, com
fallback automático entre provedores free quando um estoura quota.

> **Não é só free:** o hub aceita **APIs pagas** e **provedores self-hosted**
> (OpenAI-compatible) também — tudo vira provider no OmniRoute. Veja
> [APIs pagas e self-hosted](#apis-pagas-e-self-hosted).

## Arquitetura

```
fcc-claude (qualquer terminal)          [cliente agente — global via uv]
  → fcc-server  (porta 8084)            [gateway do free-claude-code]
    → LiteLLM   (porta 4001)            [ponte Anthropic /v1/messages → OpenAI]
      → OmniRoute (porta 20128)         [gateway free-tier: fallback + telemetria]
        → combo "free-agent" (priority, maxRetries:0)
            1. nvidia/deepseek-ai/deepseek-v4-flash-0731   (PRIMÁRIO)
            2. gemini/gemini-3.5-flash                     (fallback 1)
            3. mistral/mistral-medium-3-5                  (fallback 2)
        → free-agent-small → nvidia/deepseek-ai/deepseek-v4-flash-0731 (pinado)
```

- Todos os backends são **free tiers oficiais**, OpenAI-compatíveis.
- O LiteLLM usa o caminho `openai/` + `LITELLM_USE_CHAT_COMPLETIONS_URL_FOR_ANTHROPIC_MESSAGES=true` — o mesmo já validado no stack local. A ponte Anthropic→chat/completions e o patch de thinking são preservados intactos.
- **Fallback no OmniRoute**: combo `free-agent` com estratégia `priority` esgota o 1º alvo antes de deslizar pro próximo (`maxRetries:0`, sem reenvio duplicado de tool-calls). O header `x-omniroute-decision` mostra a rota usada (`strategy=priority; provider=…`).
- **Dashboard**: `http://127.0.0.1:20128` (senha = `OMNIROUTE_ADMIN_PASSWORD` em `env/.env.omniroute`).
- Portas dedicadas (4001/8084/20128) — **não interfere** nas instâncias existentes do
  fcc (DeepSeek 8082, local 8083) nem no stack `~/Documents/LLM` (4000).

## Quickstart

```bash
# 1) Uma vez:
cd ~/Documents/ai-hub && ./setup.sh          # venv + litellm + symlinks

# 2) Chaves gratuitas (env/.env.free):
#    NIM_API_KEY     → https://build.nvidia.com
#    GEMINI_API_KEY  → https://aistudio.google.com/apikey
#    MISTRAL_API_KEY → https://console.mistral.ai
#    (só NIM já basta pro primário)

# 3) Subir a infra (terminal A):
ai-up

# 4) Abrir o cliente (terminal B):
ai-code
```

Pré-requisito: `free-claude-code` (fcc) já instalado globalmente via uv
(`fcc-server`/`fcc-claude` no PATH), `uv`, `curl` e **Node.js 24+** (OmniRoute).
O `setup.sh` instala o OmniRoute global e gera `env/.env.omniroute` (chmod 600,
gitignored).

Para voltar ao comportamento da fase 1 (fallback no LiteLLM, sem OmniRoute):
`AIHUB_ROUTER=direct ai-up`.

## Comandos

| Comando | O que faz |
|---|---|
| `ai-up` | sobe OmniRoute (20128) + LiteLLM (4001) + fcc-server (8084), aplica o patch de thinking |
| `ai-up` (modo fase 1) | `AIHUB_ROUTER=direct ai-up` — pula o OmniRoute, fallback no LiteLLM |
| `ai-down` | para a infra (só as portas do ai-hub) |
| `ai-code` | abre o cliente fcc-claude apontando pro ai-hub |
| `./setup.sh` | (re)prepara venv, symlinks, OmniRoute e skills (idempotente) |

Logs: `logs/litellm.log`, `logs/fcc-aihub.log` e `logs/omniroute.log`.

## Como funciona o fallback

O combo `free-agent` no OmniRoute é o roteador: estratégia `priority` tenta a NIM
(primário) e, se falhar (chave inválida/429/5xx/timeout), desliza pro Gemini e
depois Mistral. `maxRetries:0` espelha o `num_retries:0` da fase 1 — sem reenvio
duplicado de tool-calls. O header `x-omniroute-decision` mostra a rota usada.

O dashboard do OmniRoute mostra consumo/quota por provedor
(`http://127.0.0.1:20128`, senha em `env/.env.omniroute`).

## Trocar/expandir modelos

- **Trocar a ordem do fallback:** atualize o combo no OmniRoute (via dashboard ou
  `omniroute api combos`) e o `COMBO_JSON` em `bin/up`.
- **Adicionar um provedor:** chave nova em `env/.env.free` + entrada no seeder
  `scripts/seed-omniroute-keys.mjs` (`provider_id → VAR`), depois
  `ai-down && ai-up`.
- **Listar modelos disponíveis na NIM:**
  `curl -s https://integrate.api.nvidia.com/v1/models -H "Authorization: Bearer $NIM_API_KEY"`
- **Atenção a modelos com data de expiração:** ids NIM sem sufixo expiram (o
  `deepseek-v4-flash` virou `deepseek-v4-flash-0731` em 2026-08-07). Ao ver um
  410 `end of life` no smoke test, liste o catálogo acima e atualize o combo.

### Provedores free — chaves, sites e model ids

O hub hoje tem chaves de **9 provedores** (todas em `env/.env.free`, gitignored):
NIM (primário), Gemini, Mistral, **Groq**, **Cerebras**, **OpenRouter**,
**DeepInfra**, **SambaNova** e **Dahl**. Faltam: HuggingFace e UncloseAI.

| Provedor (`provider_id`) | Destaque | Onde gerar a chave |
|---|---|---|
| NVIDIA NIM (`nvidia`) | **primário** — DeepSeek V4 Flash 0731 | https://build.nvidia.com |
| Gemini (`gemini`) | fallback 1 | https://aistudio.google.com/apikey |
| Mistral (`mistral`) | fallback 2 | https://console.mistral.ai |
| Groq (`groq`) | Llama 3.3 70B/Qwen em ASIC, latência baixíssima | https://console.groq.com/keys |
| Cerebras (`cerebras`) | GLM/Qwen/Llama em wafer-scale | https://cloud.cerebras.ai/platform/account/api-keys |
| OpenRouter (`openrouter`) | 400+ modelos (deepseek, nemotron `:free`…) | https://openrouter.ai/keys |
| DeepInfra (`deepinfra`) | DeepSeek V4 Flash, Kimi K2.5, GLM-5, R1 | https://deepinfra.com/dash/api_keys |
| SambaNova (`sambanova`) | DeepSeek V3.2, MiniMax M2.7 | https://cloud.sambanova.ai/account/keys |
| Dahl (`dahl`) | MiniMax M2.7, Kimi K2.6, DeepSeek V4 Flash | https://inference.dahl.global (token via fingerprint) |
| HuggingFace (`huggingface`) | inferência do hub (Qwen, DeepSeek…) | https://huggingface.co/settings/tokens (Access Token) |
| UncloseAI (`uncloseai`) | DeepSeek sem cadastro | https://uncloseai.com |

Model ids para usar nos combos (confirmados por catálogo em 2026-08-14):

```
groq/llama-3.3-70b-versatile
cerebras/zai-glm-4.7
openrouter/deepseek/deepseek-v4-flash-0731        (ou qualquer id do OpenRouter)
deepinfra/deepseek-ai/DeepSeek-V4-Flash-0731
sambanova/DeepSeek-V3.2
dahl/deepseek-ai/DeepSeek-V4-Flash-0731
```

> Para **adicionar um provedor**: chave em `env/.env.free` + entrada no seeder
> `scripts/seed-omniroute-keys.mjs` (`["provider_id","VAR_API_KEY"]`), depois
> `ai-down && ai-up` (troca de chave exige restart). Para **usar num combo**,
> crie/atualize o combo no dashboard (`http://127.0.0.1:20128`) ou via
> `omniroute api combos` e reinicie. Confirmar catálogo:
> `curl -s <API>/v1/models -H "Authorization: Bearer $KEY"`.

## Detalhes do OmniRoute (notas de operação)

- **Config não é YAML**: env vars + SQLite em `data/omniroute/` (`DATA_DIR`).
- **1º boot**: o servidor cria o DB sozinho (130 migrações) e grava a senha do
  dashboard a partir de `INITIAL_PASSWORD` (= `OMNIROUTE_ADMIN_PASSWORD` do
  `env/.env.omniroute`, exportado pelo `ai-up`). NÃO rodar `omniroute setup`
  manualmente — o CLI cria um DB minimalista que o servidor rejeita no boot.
- **Trocar chave exige restart**: `ai-down && ai-up` (o gateway cacheia conexões
  em memória).
- **Apple Silicon**: o `setup.sh` copia o `better-sqlite3` `darwin-arm64` pro
  `dist/` do pacote (o bundle só traz prebuilds x64).

## Centralização global (skills · MCPs · conhecimento)

Este folder é a **fonte de verdade** do que você usa em todos os projetos:

- `skills/` → symlinked em `~/.claude/skills/` pelo `setup.sh` (globais no
  Claude Code). Veja `skills/README.md`. As skills do Matt Pocock vivem no
  submódulo `vendor/mattpocock-skills` — ao clonar: `git submodule update --init`.
- `mcp/` → futuros servidores MCP globais (ver `mcp/README.md`).
- `knowledge/` → futuras bases de conhecimento (ver `knowledge/README.md`).

> Planejamento, PRD e Issues **não ficam aqui** — ficam em cada projeto.

## APIs pagas e self-hosted

O hub nasceu para custo zero, mas o roteador (OmniRoute) não discrimina
provedor — tudo entra igual: chave + combo.

- **APIs pagas** (OpenAI, Anthropic, etc.): `omniroute keys add openai sk-...`
  (ou `["openai","OPENAI_API_KEY"]` no `scripts/seed-omniroute-keys.mjs`),
  depois um combo dedicado (ex.: `premium`) e chamar `model: premium`. Dá para
  usar só para tarefas específicas via curl, sem mexer no fcc.
- **Self-hosted** (ex.: um stack local MLX/Ollama): o OmniRoute tem providers
  OpenAI-compatible prontos (Ollama, vLLM, LM Studio, Llamafile, llama-server,
  Triton…) — basta apontar a base URL para o endpoint local (ex.: LiteLLM na
  porta 4000) e adicionar a "chave" (opcional) + combo.

Para **priorizar qual API consumir**, a estratégia `priority` do combo usa a
ordem do array `models` (1º = preferido; os seguintes são fallback quando o 1º
falha). Outras estratégias: `weighted`, `round-robin`, `least-used`,
`cost-optimized`, `reset-aware`, `headroom`, etc.

## Referências externas

- **LiteLLM** — https://github.com/BerriAI/litellm · https://docs.litellm.ai
  (ponte Anthropic `/v1/messages` → OpenAI `/chat/completions` que o hub usa na
  porta 4001, junto com o patch de thinking)
- **OmniRoute** — https://github.com/diegosouzapw/OmniRoute
  (gateway free-tier na porta 20128: fallback, telemetria, dashboard)
- **free-claude-code** — cliente agente (fcc-claude/fcc-server, porta 8084);
  instalado globalmente via `uv`, como qualquer CLI `claude` no PATH

## Troubleshooting

- **`401`/`403` nas respostas:** chave faltando ou errada em `env/.env.free`
  (o `ai-up` avisa qual está `sk-NAO-CONFIGURADO`).
- **Fallback pulando pro Mistral (sem passar pelo Gemini):** provider id errado
  no combo. O id real do Gemini no catálogo é `gemini` (não `google`) — veja
  `scripts/seed-omniroute-keys.mjs`.
- **`ai-down` deixa porta 20128 ocupada:** versões antigas do `bin/down` matavam
  só o listener; o wrapper `omniroute serve` sobrevivia e respawnava o filho.
  Rode `pkill -f "omniroute serve --port 20128"` para limpar manualmente.
- **`MigrationSafetyAbortError` no boot:** alguém rodou `omniroute setup` —
  apague `data/omniroute/storage.sqlite*` e rode `ai-up` (o servidor recria).
- **Resposta demorada:** contexto grande em free tier pode demorar (prefill na
  nuvem ainda é rápido, mas quota/throttle atrasam). `HTTP_READ_TIMEOUT=300` já
  dá folga.
- **Thinking:** OFF por padrão (`ENABLE_MODEL_THINKING=false`). Para ligar,
  troque para `true` e confirme que o patch do litellm aplicou (log do `ai-up`).
