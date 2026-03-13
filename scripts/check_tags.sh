#!/usr/bin/env bash

# =========================
# Configuración global
# =========================
ARCH="amd64"
OS="linux"
PAGE_SIZE=100

# =========================
# Parámetros
# =========================
INPUT="$1"

if [[ -z "$INPUT" ]]; then
  echo "Uso: $0 <imagen> o $0 <imagen>:<tag>"
  echo "Ejemplo: $0 linuxserver/nextcloud"
  echo "         $0 zabbix/zabbix-server-mysql:6.0-alpine-latest"
  exit 1
fi

# Separar imagen y tag (default: latest)
if [[ "$INPUT" == *":"* ]]; then
  IMAGE="${INPUT%%:*}"
  REF_TAG="${INPUT##*:}"
else
  IMAGE="$INPUT"
  REF_TAG="latest"
fi

BASE_URL="https://hub.docker.com/v2/repositories/${IMAGE}/tags"

# =========================
# 1) Digest del tag de referencia
# =========================
LATEST_DIGEST=$(curl -s "${BASE_URL}/${REF_TAG}" \
  | jq -r --arg ARCH "$ARCH" --arg OS "$OS" '
    .images[]
    | select(.architecture==$ARCH and .os==$OS)
    | .digest')

if [[ -z "$LATEST_DIGEST" || "$LATEST_DIGEST" == "null" ]]; then
  echo "No se pudo obtener digest ${OS}/${ARCH} para ${IMAGE}:latest"
  exit 2
fi

# =========================
# Salida en tabla
# =========================
printf "%-30s %-15s\n" "TAG" "DIGEST"
printf "%-30s %-15s\n" "------------------------------" "---------------"

# =========================
# 2) Iterar tags (paginado)
# =========================
URL="${BASE_URL}?page_size=${PAGE_SIZE}"

while [[ -n "$URL" && "$URL" != "null" ]]; do
  RESP=$(curl -s "$URL")

echo "$RESP" | jq -r \
  --arg DIG "$LATEST_DIGEST" \
  --arg ARCH "$ARCH" \
  --arg OS "$OS" '
  .results[]
  | select(.images != null)
  | .name as $tag
  | (.images[]
      | select(.architecture==$ARCH and .os==$OS)
      | .digest) as $digest
  | select($digest == $DIG)
  | [$tag, ($digest | sub("^sha256:";"") | .[0:12])]
  | @tsv
' | while IFS=$'\t' read -r TAG DIG; do
    printf "%-30s %-15s\n" "$TAG" "$DIG"
  done

  URL=$(echo "$RESP" | jq -r '.next')
done``
