#!/bin/bash
#============================================================================
# PRbot - Monitoramento Automatizado de Pull Requests via GitHub API
# Autor: Arthur Soares Higino - 20213012893
#============================================================================

# Configurações
WEBHOOK_URL="https://hooks.slack.com/services/TXXXXX/BXXXXX/XXXXXXXXXXXXXXXX"
LOG_DIR="./logs"
declare -i LIMITE_DIAS=3
declare -i TOTAL_PRS=0

# Nome do log com data/hora
DATA_EXECUCAO=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_FILE="${LOG_DIR}/prbot_${DATA_EXECUCAO}.log"

# Validação de argumentos
if [ $# -ne 1 ]; then
    echo "Uso: $(basename "$0") <owner/repo>"
    echo "Exemplo: $(basename "$0") cli/cli"
    exit 1
fi

REPO="$1"

# Valida formato owner/repo
if [[ ! "$REPO" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]]; then
    echo "[ERRO] Formato inválido. Use: owner/repo" >&2
    exit 1
fi

# Separa owner e nome do repo
OWNER="${REPO%/*}"
REPO_NAME="${REPO#*/}"

# Cria diretório de logs com permissão restrita
mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"

# Arquivo temporário + limpeza automática ao sair
TMPFILE=$(mktemp /tmp/prbot.XXXXXX)
trap 'rm -f "$TMPFILE" "${TMPFILE}.report" "${TMPFILE}.parsed"' EXIT INT TERM

echo "[$(date '+%Y-%m-%d %H:%M:%S')] PRbot iniciado" >> "$LOG_FILE"
echo "[INFO] Consultando ${OWNER}/${REPO_NAME}..." >> "$LOG_FILE"

# Busca PRs abertos na API do GitHub
curl -s "https://api.github.com/repos/${REPO}/pulls?state=open&per_page=30" \
    > "$TMPFILE" 2>> "$LOG_FILE"

# Verifica se a requisição teve sucesso
[ $? -eq 0 ] && echo "[OK] API respondeu" >> "$LOG_FILE" \
              || { echo "[ERRO] Falha na requisição" >> "$LOG_FILE"; exit 1; }

# Verifica se há PRs no JSON retornado
if ! grep -qE '"number":[[:space:]]*[0-9]+' "$TMPFILE"; then
    echo "[INFO] Nenhum PR aberto em ${REPO}" >> "$LOG_FILE"
    echo "Nenhum PR aberto encontrado em ${REPO}."
    exit 0
fi

# Extrai número, título, autor e data de cada PR com AWK
awk -F'"' '
/"number":/ && !got_num { gsub(/[^0-9]/,"",$0); num=$0; got_num=1 }
/"title":/ && !got_title { title=$4; got_title=1 }
/"login":/ && !got_author { author=$4; got_author=1 }
/"created_at":/ && !got_date { date=$4; got_date=1 }
/^  \},?$/ || /^  \]/ {
    if (num && title) print num "|" title "|" author "|" date
    num=""; title=""; author=""; date=""
    got_num=0; got_title=0; got_author=0; got_date=0
}
' "$TMPFILE" > "${TMPFILE}.parsed"

# Processa cada PR extraído
while IFS='|' read -r PR_NUM PR_TITLE PR_AUTHOR PR_DATE; do

    # Pula linhas inválidas
    if [ -z "$PR_NUM" ] || [ -z "$PR_DATE" ]; then
        continue
    fi

    # Converte data ISO (2026-06-01T...) para formato numérico (20260601)
    DATA_CRIACAO=$(echo "$PR_DATE" | sed 's/T.*//; s/-//g')

    # Calcula quantos dias o PR está aberto
    # macOS usa "date -j -f", Linux usa "date -d"
    EPOCH_CRIACAO=$(date -j -f "%Y%m%d" "$DATA_CRIACAO" "+%s" 2>/dev/null \
                 || date -d "$DATA_CRIACAO" "+%s" 2>/dev/null)
    EPOCH_HOJE=$(date "+%s")
    DIAS_ABERTO=$(( (EPOCH_HOJE - ${EPOCH_CRIACAO:-$EPOCH_HOJE}) / 86400 ))

    # Calcula prioridade: quanto mais dias aberto, maior a urgência
    PRIORIDADE=$(( DIAS_ABERTO / LIMITE_DIAS ))
    [ $PRIORIDADE -gt 5 ] && PRIORIDADE=5
    [ $PRIORIDADE -lt 1 ] && PRIORIDADE=1

    # Atribui emoji conforme prioridade
    case $PRIORIDADE in
        5) EMOJI="🔥" ; URGENCIA="CRITICO"  ;;
        4) EMOJI="🚀" ; URGENCIA="URGENTE"  ;;
        3) EMOJI="📅" ; URGENCIA="MEDIO"    ;;
        2) EMOJI="☕" ; URGENCIA="BAIXO"    ;;
        *) EMOJI="💤" ; URGENCIA="NORMAL"   ;;
    esac

    # Grava linha formatada no relatório temporário
    printf "%d|%s %s #%s - %s (@%s) - %d dias aberto\n" \
        "$PRIORIDADE" "$EMOJI" "$URGENCIA" \
        "$PR_NUM" "$PR_TITLE" "$PR_AUTHOR" "$DIAS_ABERTO" \
        >> "${TMPFILE}.report"

    TOTAL_PRS=$((TOTAL_PRS + 1))

done < "${TMPFILE}.parsed"

# Monta o relatório final ordenado por prioridade
NUM_CRITICOS=$(grep -c "CRITICO\|URGENTE" "${TMPFILE}.report" 2>/dev/null)
NUM_CRITICOS=${NUM_CRITICOS:-0}

# Ordena por prioridade (maior primeiro), remove coluna de sort, limita a 20
RELATORIO=$(sort -t'|' -k1 -nr "${TMPFILE}.report" | sed 's/^[0-9]*|//' | head -20)

# Grava resumo no log
{
    echo "[RESUMO] PRs analisados: ${TOTAL_PRS}"
    echo "[RESUMO] PRs críticos/urgentes: ${NUM_CRITICOS}"
    echo "────────────────────────"
    echo "$RELATORIO"
    echo "────────────────────────"
} >> "$LOG_FILE"

# Monta mensagem para o Slack
HEADER="*PRbot - ${REPO}*  ($(date '+%d/%m/%Y %H:%M'))"
FOOTER="_Total: ${TOTAL_PRS} PRs | Críticos: ${NUM_CRITICOS}_"

# Escapa caracteres que quebram JSON e converte quebras de linha
RELATORIO_SAFE=$(printf '%s' "$RELATORIO" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' '§' | sed 's/§/\\n/g')

# Envia para o webhook do Slack via HTTP POST
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" \
    -d "{\"text\": \"${HEADER}\\n────────────────────────\\n${RELATORIO_SAFE}\\n────────────────────────\\n${FOOTER}\"}" \
    "$WEBHOOK_URL")

# Verifica resultado do envio
if [ "$RESPONSE" = "200" ]; then
    echo "[OK] Relatório enviado para Slack (HTTP ${RESPONSE})" >> "$LOG_FILE"
else
    echo "[ERRO] Falha ao enviar para Slack (HTTP ${RESPONSE})" >> "$LOG_FILE"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] PRbot finalizado" >> "$LOG_FILE"
echo "PRbot concluído. ${TOTAL_PRS} PRs analisados. Log: $LOG_FILE"
