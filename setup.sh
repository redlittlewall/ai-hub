#!/usr/bin/env bash
# =============================================================================
# setup.sh — prepara o ai-hub (rodar UMA vez).
#   1. cria .venv (python 3.12 via uv, espelhando o stack local)
#   2. instala litellm 1.95.0 + fastapi<0.141 (gotcha conhecido)
#   3. cria env/.env.free a partir do .env.free.example (se não existir)
#   4. symlinks globais: ~/.local/bin/{ai-up,ai-down,ai-code}
#   5. symlinks das skills: ~/.claude/skills/*  ←  ai-hub/skills/*
#
# Idempotente — pode rodar de novo a qualquer momento.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "▶ 1/6 Criando venv (python 3.12)..."
if [ ! -d .venv ]; then
  if command -v uv >/dev/null 2>&1; then
    uv venv --python 3.12 .venv
  else
    PY="python3.12"; command -v "$PY" >/dev/null 2>&1 || PY="python3"
    "$PY" -m venv .venv
    echo "   (uv não encontrado — usei $PY; python >=3.10 é necessário)"
  fi
else
  echo "   .venv já existe — ok."
fi

echo "▶ 2/6 Instalando litellm[proxy] 1.95.0 + fastapi==0.140.0..."
# fastapi ==0.140.0 EXATO (não apenas <0.141): o 0.140.13 já removeu
# get_flat_dependant, que o litellm 1.95 usa. Gotcha documentado no stack local.
if command -v uv >/dev/null 2>&1; then
  uv pip install --python .venv/bin/python -q "fastapi==0.140.0" "litellm[proxy]==1.95.0"
else
  .venv/bin/pip install -q --upgrade pip
  .venv/bin/pip install -q "fastapi==0.140.0" "litellm[proxy]==1.95.0"
fi

echo "▶ 3/6 Env de chaves..."
if [ ! -f env/.env.free ]; then
  cp env/.env.free.example env/.env.free
  echo "   criado env/.env.free — preencha as chaves antes do ai-up."
else
  echo "   env/.env.free já existe — ok."
fi

echo "▶ 4/6 Symlinks globais em ~/.local/bin..."
chmod +x bin/up bin/down bin/claude scripts/patch-litellm-thinking.py
mkdir -p "$HOME/.local/bin"
ln -sf "$ROOT/bin/up"     "$HOME/.local/bin/ai-up"
ln -sf "$ROOT/bin/down"   "$HOME/.local/bin/ai-down"
ln -sf "$ROOT/bin/claude" "$HOME/.local/bin/ai-code"
echo "   ai-up · ai-down · ai-code  (já estão no PATH: ~/.local/bin)"

echo "▶ 5/6 Skills globais (~/.claude/skills ← ai-hub/skills)..."
mkdir -p "$HOME/.claude/skills"
linked=0
for d in "$ROOT"/skills/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  ln -sfn "$d" "$HOME/.claude/skills/$name"
  echo "   skills/$name → ~/.claude/skills/$name"
  linked=1
done
[ "$linked" = 1 ] || echo "   (nenhuma skill ainda — crie pastas em skills/ e rode de novo)"

echo "▶ 6/6 OmniRoute (gateway free-tier, porta 20128)..."
# Node 24+ é exigência do OmniRoute (engines.node)
node_major="$(node -v 2>/dev/null | sed -E 's/v([0-9]+).*/\1/')"
if [ -z "$node_major" ] || [ "$node_major" -lt 24 ]; then
  echo "   ⚠  Node.js 24+ necessário (tem: $(node -v 2>/dev/null || echo nenhum))."
  echo "      Instale via nvm antes do ai-up — sem omniroute o hub não sobe."
else
  if ! command -v omniroute >/dev/null 2>&1; then
    echo "   instalando omniroute global (npm install -g omniroute)..."
    npm install -g omniroute
  else
    echo "   omniroute já instalado: $(omniroute -v 2>/dev/null | grep -v "Loaded env" | head -1)"
  fi

  # better-sqlite3 darwin-arm64: o bundle do dist/ só traz prebuilds x64; na
  # Apple Silicon o servidor morre com "disk I/O error" na sonda do
  # instrumentation. A raiz do pacote (npm -g) TEM o darwin-arm64.node (N-API,
  # ABI-stável) — copia pro dist/ se faltar. Idempotente.
  OR_ROOT="$(npm root -g)/omniroute"
  if [ -f "$OR_ROOT/dist/node_modules/better-sqlite3/prebuilds/darwin-x64.node" ] \
     && [ ! -f "$OR_ROOT/dist/node_modules/better-sqlite3/prebuilds/darwin-arm64.node" ] \
     && [ -f "$OR_ROOT/node_modules/better-sqlite3/prebuilds/darwin-arm64.node" ]; then
    cp "$OR_ROOT/node_modules/better-sqlite3/prebuilds/darwin-arm64.node" \
       "$OR_ROOT/dist/node_modules/better-sqlite3/prebuilds/darwin-arm64.node"
    echo "   ✓ copiado better-sqlite3 darwin-arm64 → dist/ (repair Apple Silicon)"
  fi
fi

# Env do OmniRoute (gerado UMA vez — idempotente)
OMNIROUTE_ENV="$ROOT/env/.env.omniroute"
if [ ! -f "$OMNIROUTE_ENV" ]; then
  mkdir -p "$ROOT/data"
  OMNIROUTE_ADMIN_PASSWORD="$(openssl rand -hex 16)"
  OMNIROUTE_API_KEY="or-$(openssl rand -hex 24)"
  cat > "$OMNIROUTE_ENV" <<EOF
# Gerado por setup.sh — NÃO commitar (chaves). Regenerar = deletar o arquivo
# e rodar setup.sh de novo (as credenciais do OmniRoute em data/ ficam órfãs).
DATA_DIR=$ROOT/data/omniroute
OMNIROUTE_PORT=20128
OMNIROUTE_SERVER_HOST=127.0.0.1
REQUIRE_API_KEY=true
OMNIROUTE_API_KEY=$OMNIROUTE_API_KEY
OMNIROUTE_ADMIN_PASSWORD=$OMNIROUTE_ADMIN_PASSWORD
EOF
  chmod 600 "$OMNIROUTE_ENV"
  echo "   criado env/.env.omniroute (endpoint key + senha admin geradas)."
else
  echo "   env/.env.omniroute já existe — ok."
fi

# NÃO rodar `omniroute setup` aqui: o CLI cria um DB minimalista (migration
# tracking só em '001') que o SERVIDOR rejeita no boot (129 migrações
# pendentes → MigrationSafetyAbortError). O servidor deve criar o DB sozinho
# no 1º boot (todas as 130 migrações) e nesse momento lê INITIAL_PASSWORD do
# env (exportado pelo bin/up) para gravar a senha do dashboard. DB deixa de
# existir → o próximo ai-up recria do zero (idempotente).
if command -v omniroute >/dev/null 2>&1; then
  set -a; source "$OMNIROUTE_ENV"; set +a
  if [ ! -f "$DATA_DIR/storage.sqlite" ]; then
    echo "   (storage.sqlite ainda não existe — o 1º ai-up vai inicializar o"
    echo "    DB do OmniRoute com a senha de env/.env.omniroute)"
  else
    echo "   storage.sqlite já existe — ok."
  fi
fi

echo
echo "✅ Setup concluído."
echo "   Próximo: 1) preencher env/.env.free  2) ai-up  3) ai-code (em outro terminal)"
echo "   ai-up agora também sobe o OmniRoute (20128) — dashboard: http://127.0.0.1:20128"
