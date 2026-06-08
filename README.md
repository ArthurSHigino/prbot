# PRbot

Monitoramento Automatizado de Pull Requests via GitHub API.

Shell script que consulta a API do GitHub, identifica PRs abertos em um repositório, calcula há quantos dias cada um está aguardando revisão e ajusta a prioridade dinamicamente. O relatório é enviado para um webhook do Slack e salvo em log local.

## Uso

```bash
./prbot.sh <owner/repo>
```

## Exemplo

```bash
./prbot.sh cli/cli
```

## Configuração

Edite a variável `WEBHOOK_URL` no início do script com a URL do seu webhook do Slack.

Caso não configure um webhook, o script funciona normalmente — o relatório completo fica disponível no arquivo de log em `./logs/`.

## Requisitos

- bash
- curl
- awk, sed, grep (incluídos em qualquer sistema Unix)

## Saída

O script gera:
- **Webhook Slack**: relatório formatado enviado via HTTP POST
- **Log local**: arquivo em `./logs/prbot_YYYY-MM-DD_HH-MM-SS.log` com o relatório completo
