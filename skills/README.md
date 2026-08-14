# skills/ — skills globais (fonte de verdade)

Cada subpasta aqui é uma **skill** usada em todos os projetos. O `setup.sh`
cria symlinks em `~/.claude/skills/` (o diretório de skills pessoais do Claude
Code), então basta criar a pasta aqui e rodar `./setup.sh` de novo.

## Convenção

```
skills/
└── <nome-da-skill>/
    ├── SKILL.md        # instruções da skill (obrigatório)
    └── ...             # assets/scripts da skill (opcional)
```

- Nome em kebab-case, descritivo.
- `SKILL.md` segue o formato de skill do Claude Code (frontmatter + corpo).
- Não coloque aqui nada específico de um projeto — isso fica no projeto.

## Adicionar uma skill

1. Crie `skills/<nome>/SKILL.md`.
2. Rode `./setup.sh` (ou rode o symlink na mão:
   `ln -sfn ~/Documents/ai-hub/skills/<nome> ~/.claude/skills/<nome>`).

## Skills do Matt Pocock (vendor)

As skills de `github.com/mattpocock/skills` ficam no **vendor** e aparecem aqui
como symlinks — o repo original não é editado aqui dentro:

```
vendor/mattpocock-skills/          ← clone upstream (git)
  skills/engineering/*  skills/productivity/*
skills/<nome> → ../vendor/mattpocock-skills/skills/<categoria>/<nome>
```

- **Quais entram:** exatamente as 25 listadas no `.claude-plugin/plugin.json`
  upstream (18 engineering + 7 productivity) — as pastas `in-progress`,
  `misc` e `deprecated` ficam de fora de propósito.
- **Atualizar:** `git -C vendor/mattpocock-skills pull` e rodar `./setup.sh`.
  Novas skills do upstream entram com symlink manual (`skills.sh update`
  não se aplica aqui — preferimos o clone, que centraliza tudo no ai-hub).
- **`/setup-matt-pocock-skills`** é uma skill *por projeto*: rode-a dentro de um
  repo para gerar `docs/agents/`, `CONTEXT.md`, etc. Não roda globalmente.

## Remover

1. Delete a pasta `skills/<nome>/` (se for vendor, só o symlink).
2. Rode `./setup.sh` de novo (os symlinks órfãos precisam ser removidos na mão:
   `rm ~/.claude/skills/<nome>`).
