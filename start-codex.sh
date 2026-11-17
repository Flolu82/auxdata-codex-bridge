#!/usr/bin/env bash
# start-codex.sh - startet Codex mit einem Modell aus AuxData (macOS, Linux).
#
#   ./start-codex.sh                          Standardmodell, interaktiv
#   ./start-codex.sh opus                     Kurzname aus models.json
#   ./start-codex.sh mistral/mistral-medium-3-5 exec "Frage"
#   ./start-codex.sh exec "Frage"             Standardmodell, weitere Codex-Argumente
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_MODEL="anthropic/claude-sonnet-5-5"

fail() { echo "FEHLER: $*" >&2; exit 1; }

# .env neben dem Skript lesen. Werte gelten nur fuer diesen Prozess;
# bereits gesetzte Umgebungsvariablen haben Vorrang.
if [ -f "$ROOT/.env" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    name="${line%%=*}"; value="${line#*=}"
    [ "$name" = "$line" ] && continue
    name="$(printf '%s' "$name" | tr -d '[:space:]')"
    value="${value#\"}"; value="${value%\"}"
    if [ -n "$value" ] && [ -z "${!name:-}" ]; then export "$name=$value"; fi
  done < "$ROOT/.env"
fi

[ -n "${AUXDATA_API_KEY:-}" ] || fail "AUXDATA_API_KEY fehlt. Kopiere .env.example nach .env und trage deinen persoenlichen AuxData-Schluessel ein."
command -v node >/dev/null 2>&1 || fail "Node.js (ab Version 18) nicht gefunden."
command -v codex >/dev/null 2>&1 || fail "Codex CLI nicht gefunden (Befehl 'codex')."

export BRIDGE_PORT="${BRIDGE_PORT:-8790}"
# 127.0.0.1 statt localhost: die Bridge bindet nur IPv4.
BRIDGE_URL="http://127.0.0.1:$BRIDGE_PORT"

# Erstes Argument ist das Modell, wenn es eine Gateway-ID (mit Schraegstrich)
# oder ein Kurzname aus models.json ist. Sonst gilt das Standardmodell.
MODEL="$DEFAULT_MODEL"
if [ $# -gt 0 ]; then
  if [[ "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_./:-]+$ ]]; then
    MODEL="$1"; shift
  elif [[ "$1" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    resolved="$(node "$ROOT/bridge.js" --resolve "$1" | tr -d '\r\n')"
    if [ -n "$resolved" ]; then MODEL="$resolved"; shift; fi
  fi
fi

# Bridge starten, falls sie noch nicht laeuft. Sie bekommt den Schluessel nicht
# in ihre Umgebung; er kommt mit jeder Anfrage von Codex.
node "$ROOT/bridge.js" --start || exit 1

echo "-> Codex mit AuxData, Modell $MODEL (Bridge $BRIDGE_URL)" >&2

# Der Provider wird nur fuer diesen Aufruf gesetzt; ~/.codex/config.toml bleibt
# unveraendert. wire_api muss "responses" sein. "apps" sind die ChatGPT-Apps von
# OpenAI: ohne OpenAI-Anmeldung nutzlos, sie wuerden nur jede Anfrage vergroessern.
exec codex --disable apps \
  -c model_provider=auxdata \
  -c model_providers.auxdata.name=AuxData \
  -c "model_providers.auxdata.base_url=$BRIDGE_URL/v1" \
  -c model_providers.auxdata.env_key=AUXDATA_API_KEY \
  -c model_providers.auxdata.wire_api=responses \
  -m "$MODEL" "$@"
