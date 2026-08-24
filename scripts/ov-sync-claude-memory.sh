#!/usr/bin/env bash

# =========================
# ov-sync-claude-memory.sh
# Sincroniza memoria curada (.claude/memory) e historial (.history) de los
# proyectos ~/Projects/git.*/ hacia OpenViking (viking://resources/claude/<proyecto>)
#
# - Detecta cambios con checksum; solo re-importa lo modificado
# - Requiere ~/.openviking/ovcli.conf con api_key
# Uso: ov-sync-claude-memory.sh [--force]
# =========================

set -euo pipefail

PROJECTS_ROOT="${HOME}/Nextcloud/Projects"
OVCLI="${HOME}/.openviking/ovcli.conf"
STATE_DIR="${HOME}/.cache/ov-sync-claude"
STAGE_DIR=$(mktemp -d)
FORCE=false
IMPORTED_LOG=""
SKIPPED_LOG=""
FAILED_LOG=""

[[ "${1:-}" == "--force" ]] && FORCE=true
trap 'rm -rf "$STAGE_DIR"' EXIT

if [[ ! -f "$OVCLI" ]]; then
  echo "ERROR: no existe $OVCLI" >&2
  exit 2
fi
API_KEY=$(python3 -c "import json;print(json.load(open('$OVCLI'))['api_key'])")
BASE_URL=$(python3 -c "import json;print(json.load(open('$OVCLI'))['url'])" | sed 's:/*$::')

dir_checksum() {
  find "$1" -type f -print0 | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1
}

stage_zip() {
  # $1=source_dir $2=stage_dir -> imprime path del zip o vacío si no hay nada
  mkdir -p "$2"
  rsync -a --exclude '/.*' "$1/" "$2/"
  [[ -d "$2/.history" ]] && { mv "$2"/.history/* "$2"/ 2>/dev/null || true; rmdir "$2/.history" 2>/dev/null || true; }
  if [[ -z "$(ls -A "$2")" ]]; then
    return 1
  fi
  local zip_file="$STAGE_DIR/$(basename "$2").zip"
  rm -f "$zip_file"
  (cd "$2" && zip -qr "$zip_file" .)
  echo "$zip_file"
}

ov_import() {
  local zip_file="$1" to_uri="$2" reason="$3"
  local tid task_id
  tid=$(curl -sf -X POST "$BASE_URL/api/v1/resources/temp_upload" \
    -H "X-API-Key: $API_KEY" -F "file=@$zip_file" |
    python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["temp_file_id"])')
  task_id=$(curl -sf -X POST "$BASE_URL/api/v1/resources" \
    -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
    -d "{\"temp_file_id\":\"$tid\",\"to\":\"viking://resources/$to_uri\",\"reason\":\"$reason\"}" |
    python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["task_id"])')
  echo "$task_id"
}

sync_one() {
  # $1=source_dir $2=state_key $3=to_uri $4=reason
  local src="$1" key="$2" uri="$3" reason="$4"
  local sum zip_file task_id
  sum=$(dir_checksum "$src")

  if [[ "$FORCE" == false && -f "$STATE_DIR/$key.sha" ]] &&
     [[ "$(cat "$STATE_DIR/$key.sha")" == "$sum" ]]; then
    SKIPPED_LOG+="$key"$'\n'
    return 0
  fi

  if ! zip_file=$(stage_zip "$src" "$STAGE_DIR/$key"); then
    SKIPPED_LOG+="$key (vacío)"$'\n'
    return 0
  fi

  if task_id=$(ov_import "$zip_file" "$uri" "$reason"); then
    echo "$sum" > "$STATE_DIR/$key.sha"
    IMPORTED_LOG+="$key ($task_id)"$'\n'
  else
    FAILED_LOG+="$key"$'\n'
    return 0
  fi
}

mkdir -p "$STATE_DIR"

for mem_dir in "$PROJECTS_ROOT"/git.*/.claude/memory; do
  [[ -d "$mem_dir" ]] || continue
  project=$(basename "$(dirname "$(dirname "$mem_dir")")")
  sync_one "$mem_dir" "${project}-memory" "claude/${project}-memory" \
    "Memoria curada de Claude Code del proyecto $project"
done

for hist_dir in "$PROJECTS_ROOT"/git.*/.history; do
  [[ -d "$hist_dir" ]] || continue
  project=$(basename "$(dirname "$hist_dir")")
  sync_one "$hist_dir" "${project}-history" "claude/${project}-history" \
    "Historial estructurado (/history new) del proyecto $project"
done

echo "== ov-sync-claude-memory $(date '+%Y-%m-%d %H:%M') =="
n_import=$(printf '%s' "$IMPORTED_LOG" | grep -c . || true)
n_skip=$(printf '%s' "$SKIPPED_LOG" | grep -c . || true)
n_fail=$(printf '%s' "$FAILED_LOG" | grep -c . || true)
echo "Importados: $n_import | Sin cambios: $n_skip | Fallidos: $n_fail"
[[ -n "$IMPORTED_LOG" ]] && printf '  [import] %s\n' "$IMPORTED_LOG"
[[ -n "$SKIPPED_LOG" ]] && printf '  [sin cambios] %s\n' "$SKIPPED_LOG"
if [[ -n "$FAILED_LOG" ]]; then printf '  [ERROR] %s\n' "$FAILED_LOG" >&2; exit 1; fi
