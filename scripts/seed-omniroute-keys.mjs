#!/usr/bin/env node
// =============================================================================
// scripts/seed-omniroute-keys.mjs — grava as chaves dos provedores free no
// SQLite do OmniRoute (tabela provider_connections), usando a MESMA função do
// CLI (`upsertApiKeyProviderConnection` no caminho offline de `keys add`).
//
// Por que não `omniroute keys add`? O CLI valida o provider contra o catálogo
// via um parser AST que FALHA na estrutura real de providers.ts (object
// spreads) e cai num fallback de 6 ids (openai, anthropic, google, openrouter,
// groq, mistral). Resultado: `nvidia` e `gemini` são rejeitados mesmo existindo
// no catálogo real do servidor. Aqui gravamos direto — o servidor (router)
// lê as chaves de provider_connections sem esse gate.
//
// Mapeamento provider → variável de env (chaves vêm do env/.env.free, que o
// bin/up exporta):
//   nvidia  → NIM_API_KEY       (NVIDIA NIM, build.nvidia.com)
//   gemini  → GEMINI_API_KEY    (Gemini AI Studio — id do provider é "gemini",
//                                conforme frontier-labs.ts; NÃO "google", que é
//                                só o fallback do parser quebrado do CLI)
//   mistral → MISTRAL_API_KEY
//   groq        → GROQ_API_KEY      (console.groq.com/keys)
//   cerebras    → CEREBRAS_API_KEY  (cloud.cerebras.ai — wafer-scale)
//   openrouter  → OPENROUTER_API_KEY (openrouter.ai/keys — 400+ modelos, :free)
//   deepinfra   → DEEPINFRA_API_KEY (deepinfra.com — DeepSeek/Kimi/GLM)
//   sambanova   → SAMBANOVA_API_KEY (cloud.sambanova.ai)
//   dahl        → DAHL_API_KEY      (inference.dahl.global — MiniMax/Kimi/DeepSeek)
//
// Idempotente: upsert ON CONFLICT atualiza a chave existente.
// Executado pelo bin/up ANTES do `omniroute serve` (servidor parado → grava
// direto no SQLite, sem conflito de lock).
// =============================================================================
import { readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");

function loadDotEnv(file) {
  if (!existsSync(file)) return;
  for (const line of readFileSync(file, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (m && !(m[1] in process.env)) process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
}

// 1) DATA_DIR + endpoint do env do OmniRoute (env/.env.omniroute)
loadDotEnv(join(ROOT, "env/.env.omniroute"));

// 2) STORAGE_ENCRYPTION_KEY de $DATA_DIR/.env (o CLI carrega o mesmo arquivo;
//    sem ela o encryptCredential falha)
if (process.env.DATA_DIR) {
  loadDotEnv(join(process.env.DATA_DIR, ".env"));
}

const PLACEHOLDER = "sk-NAO-CONFIGURADO";
const PROVIDERS = [
  ["nvidia", "NIM_API_KEY"],
  ["gemini", "GEMINI_API_KEY"],
  ["mistral", "MISTRAL_API_KEY"],
  ["groq", "GROQ_API_KEY"],
  ["cerebras", "CEREBRAS_API_KEY"],
  ["openrouter", "OPENROUTER_API_KEY"],
  ["deepinfra", "DEEPINFRA_API_KEY"],
  ["sambanova", "SAMBANOVA_API_KEY"],
  ["dahl", "DAHL_API_KEY"],
];

// Localiza o pacote omniroute instalado globalmente (npm -g / nvm)
const globalRoot = execSync("npm root -g").toString().trim();
const orRoot = join(globalRoot, "omniroute");
if (!existsSync(join(orRoot, "bin/cli/provider-store.mjs"))) {
  console.error(`❌ omniroute não encontrado em ${orRoot} — rode setup.sh`);
  process.exit(1);
}

const { openOmniRouteDb } = await import(join(orRoot, "bin/cli/sqlite.mjs"));
const { upsertApiKeyProviderConnection } = await import(
  join(orRoot, "bin/cli/provider-store.mjs")
);

const { db } = await openOmniRouteDb();

let seeded = 0;
for (const [provider, varName] of PROVIDERS) {
  const key = process.env[varName] || "";
  if (!key || key === PLACEHOLDER) {
    console.log(`   ⚠  ${varName} não configurada — pulando ${provider}`);
    continue;
  }
  try {
    upsertApiKeyProviderConnection(db, { provider, name: provider, apiKey: key });
    console.log(`   ✓ chave ${provider} semeada (${varName})`);
    seeded++;
  } catch (err) {
    console.error(`   ✗ falha ao semear ${provider}: ${err.message}`);
  }
}

if (seeded === 0) {
  console.log("   ℹ  nenhuma chave semeada — requests vão falhar até configurar env/.env.free");
}
db.close();
