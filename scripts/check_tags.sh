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
IMAGE="$1"

if [[ -z "$IMAGE" ]]; then
  echo "Uso: $0 <imagen>"
  echo "Ejemplo: $0 linuxserver/nextcloud"
  exit 1
fi

BASE_URL="https://hub.docker.com/v2/repositories/${IMAGE}/tags"

# =========================
# 1) Digest de latest
# =========================
LATEST_DIGEST=$(curl -s "${BASE_URL}/latest" \
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
done
