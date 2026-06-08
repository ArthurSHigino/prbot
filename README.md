# PRbot

Monitoramento Automatizado de Pull Requests via GitHub API.

## Uso

```bash
./prbot.sh <owner/repo> [owner/repo2] ...
```

## Exemplo

```bash
./prbot.sh cli/cli facebook/react
```

## Configuração

Edite a variável `WEBHOOK_URL` no início do script com a URL do seu webhook do Slack.

## Requisitos

- bash
- curl
- awk, sed, grep (incluídos em qualquer sistema Unix)
