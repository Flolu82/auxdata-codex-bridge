#!/usr/bin/env bash
# start-claude.sh - startet Claude Code mit einem Claude-Modell aus AuxData (macOS, Linux).
#
#   ./start-claude.sh                 Standardmodell (Sonnet), interaktiv
#   ./start-claude.sh opus            Kurzname aus models.json
#   ./start-claude.sh anthropic/claude-fable-5-2 -p "Frage"
#   ./start-claude.sh -p "Frage"      Standardmodell, weitere Claude-Code-Argumente
#   ./start-claude.sh --direkt        ohne Bridge, mit Sonnet 4.6 und Haiku 4.5
#
# Der AuxData-Gateway hat einen eigenen Endpunkt im Anthropic-Format
# (/v1/messages). Claude Code schickt aber ab Opus 4.8 und bei allen
# 5er-Modellen Nachrichten mit role "system", die der Gateway ablehnt. Deshalb
# laeuft Claude Code hier ueber die lokale Bridge, die nur diese Nachrichten
# umsetzt. Mit --direkt geht es ohne Bridge und ohne Node, dann aber nur mit
# aelteren Modellen.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Modelle fuer --direkt: die neuesten, die Claude Code ohne Bridge annimmt.
DIRECT_SONNET="anthropic/claude-sonnet-4-6"
DIRECT_HAIKU="anthropic/claude-haiku-4-5"

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
command -v claude >/dev/null 2>&1 || fail "Claude Code nicht gefunden (Befehl 'claude')."

DIRECT=""
if [ "${1:-}" = "--direkt" ]; then DIRECT=1; shift; fi

# Kurzname aus models.json nachschlagen (ohne Node, ohne jq).
alias_of() {
  [ -f "$ROOT/models.json" ] || return 0
  sed -n "s/^[[:space:]]*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$ROOT/models.json" | head -n 1
}

BASE="${AUXDATA_BASE_URL:-https://auxdata.ai}"
BASE="${BASE%/}"

if [ -n "$DIRECT" ]; then
  OPUS="$DIRECT_SONNET"; SONNET="$DIRECT_SONNET"; HAIKU="$DIRECT_HAIKU"; MODEL="$DIRECT_SONNET"
else
  OPUS="$(alias_of opus)";     OPUS="${OPUS:-anthropic/claude-opus-5-5}"
  SONNET="$(alias_of sonnet)"; SONNET="${SONNET:-anthropic/claude-sonnet-5-5}"
  HAIKU="$(alias_of haiku)";   HAIKU="${HAIKU:-anthropic/claude-haiku-5-5}"
  MODEL="$SONNET"
  # Erstes Argument ist das Modell, wenn es ein Kurzname oder eine Gateway-ID ist.
  if [ $# -gt 0 ]; then
    if [[ "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_./:-]+$ ]]; then
      MODEL="$1"; shift
    elif [[ "$1" =~ ^[A-Za-z0-9_.-]+$ ]] && [ -n "$(alias_of "$1")" ]; then
      MODEL="$(alias_of "$1")"; shift
    fi
  fi
  command -v node >/dev/null 2>&1 || fail "Node.js (ab Version 18) nicht gefunden. Ohne Node geht nur './start-claude.sh --direkt'."
  export BRIDGE_PORT="${BRIDGE_PORT:-8790}"
  node "$ROOT/bridge.js" --start || exit 1
  # 127.0.0.1 statt localhost: die Bridge bindet nur IPv4.
  BASE="http://127.0.0.1:$BRIDGE_PORT"
fi

# Adresse ohne /v1: Claude Code haengt /v1/messages selbst an.
export ANTHROPIC_BASE_URL="$BASE"
# Der Schluessel geht als "Authorization: Bearer ..." an den Gateway.
export ANTHROPIC_AUTH_TOKEN="$AUXDATA_API_KEY"
# Ein zusaetzlich gesetzter ANTHROPIC_API_KEY wuerde mit dem Token konkurrieren.
unset ANTHROPIC_API_KEY
# Der Gateway kennt die Modelle nur mit dem Praefix "anthropic/".
export ANTHROPIC_MODEL="$MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$OPUS"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$SONNET"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$HAIKU"
# Keine Telemetrie, Fehlerberichte und Update-Pruefungen an Anthropic.
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

echo "-> Claude Code mit AuxData, Modell $MODEL ($ANTHROPIC_BASE_URL)" >&2
exec claude "$@"
