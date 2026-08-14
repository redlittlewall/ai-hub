# mcp/ — futuros MCPs globais

Lugar para **servidores MCP** que você quer disponíveis em todos os projetos.

**Convenção (planejada):** cada MCP fica em `mcp/<nome>/` (código/config). O
registro global vai em `~/.claude.json` (campo `mcpServers`) apontando para o
caminho daqui — ou, se o servidor for local, via `claude mcp add --scope user`.

> Ainda vazio — o mecanismo será documentado aqui quando o primeiro MCP entrar.
