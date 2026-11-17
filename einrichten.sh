#!/usr/bin/env bash
# einrichten.sh - richtet den Zugang zu AuxData ein (macOS, Linux).
#
#   ./einrichten.sh             fragt den Schluessel ab, prueft ihn und schreibt .env
#   ./einrichten.sh --pruefen   prueft nur den vorhandenen Schluessel, aendert nichts
#
# Der Schluessel wird verdeckt eingegeben, nie angezeigt und nur in die Datei
# .env neben diesem Skript geschrieben.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT/.env"
DEFAULT_BASE="https://auxdata.ai"
CHECK_ONLY=""
[ "${1:-}" = "--pruefen" ] && CHECK_ONLY=1

fail() { echo "FEHLER: $*"; exit 1; }

# Wert einer Variable aus .env lesen (ohne die Datei auszufuehren).
env_value() {
  [ -f "$ENV_FILE" ] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$ENV_FILE" | head -n 1 | tr -d '\r"'
}

echo
echo "AuxData-Zugang fuer Codex und Claude Code"
echo "-----------------------------------------"

if [ -n "$CHECK_ONLY" ]; then
  KEY="${AUXDATA_API_KEY:-$(env_value AUXDATA_API_KEY)}"
  BASE="${AUXDATA_BASE_URL:-$(env_value AUXDATA_BASE_URL)}"
  BASE="${BASE:-$DEFAULT_BASE}"
  [ -n "$KEY" ] || fail "Kein Schluessel gefunden. Starte ./einrichten.sh ohne --pruefen."
else
  if [ -f "$ENV_FILE" ]; then
    read -r -p "Es gibt schon eine .env. Ueberschreiben? [j/N]: " answer || answer=""
    case "$answer" in
      [jJyY]*) ;;
      *) echo "Nichts geaendert. Mit \"./einrichten.sh --pruefen\" pruefst du den vorhandenen Schluessel."; exit 0 ;;
    esac
  fi
  echo "Den Schluessel erzeugst du in AuxData: Avatar-Menue -> Persoenliche Einstellungen"
  echo "-> Karte \"API-Schluessel\" -> neuen Schluessel erzeugen. Er wird nur einmal angezeigt."
  echo
  read -r -s -p "Persoenlicher AuxData-Schluessel (Eingabe bleibt unsichtbar): " KEY || KEY=""
  echo
  KEY="$(printf '%s' "$KEY" | tr -d '[:space:]')"
  [ -n "$KEY" ] || fail "Kein Schluessel eingegeben. Nichts gespeichert."
  case "$KEY" in
    sk-auxdata-*) ;;
    *) echo "Hinweis: AuxData-Schluessel beginnen mit \"sk-auxdata-\". Ich pruefe ihn trotzdem." ;;
  esac
  read -r -p "Adresse deiner AuxData-Instanz [Enter = $DEFAULT_BASE]: " BASE || BASE=""
  BASE="$(printf '%s' "$BASE" | tr -d '[:space:]')"
  BASE="${BASE:-$DEFAULT_BASE}"
fi
BASE="${BASE%/}"
case "$BASE" in
  http://*|https://*) ;;
  *) fail "Die Adresse muss mit https:// beginnen: $BASE" ;;
esac

# Schluessel pruefen: Der Gateway nennt die Modelle, die er fuer diesen
# Schluessel fuehrt. Der Schluessel geht ueber die Standardeingabe an curl,
# damit er nicht in der Prozessliste steht.
echo
echo "Pruefe den Schluessel an $BASE/v1/models ..."
BODY="$(mktemp)"
trap 'rm -f "$BODY"' EXIT
STATUS="000"
if command -v curl >/dev/null 2>&1; then
  STATUS="$(printf 'header = "Authorization: Bearer %s"\n' "$KEY" | curl -sS -m 30 -K - -o "$BODY" -w '%{http_code}' "$BASE/v1/models" 2>/dev/null || true)"
elif command -v node >/dev/null 2>&1; then
  STATUS="$(AUXDATA_API_KEY="$KEY" CHECK_URL="$BASE/v1/models" CHECK_OUT="$BODY" node -e '
    fetch(process.env.CHECK_URL, { headers: { Authorization: "Bearer " + process.env.AUXDATA_API_KEY }, signal: AbortSignal.timeout(30000) })
      .then(async (r) => { require("fs").writeFileSync(process.env.CHECK_OUT, await r.text()); console.log(r.status); })
      .catch(() => console.log("000"));' || true)"
else
  fail "Weder curl noch node gefunden; damit laesst sich der Schluessel nicht pruefen."
fi
STATUS="${STATUS:-000}"

PROBLEM=""
case "$STATUS" in
  200) COUNT="$(grep -o '"id"' "$BODY" | wc -l | tr -d '[:space:]')"
       echo "Der Schluessel gilt. Der Gateway fuehrt $COUNT Modelle." ;;
  401|403) fail "AuxData hat den Schluessel abgelehnt (Status $STATUS). Nichts gespeichert. Erzeuge einen neuen Schluessel und versuch es noch einmal." ;;
  000) PROBLEM="Keine Verbindung zu $BASE." ;;
  *) PROBLEM="AuxData antwortet mit Status $STATUS." ;;
esac

if [ -n "$PROBLEM" ]; then
  echo "$PROBLEM"
  [ -z "$CHECK_ONLY" ] || exit 1
  read -r -p "Der Schluessel ist nicht geprueft. Trotzdem speichern? [j/N]: " answer || answer=""
  case "$answer" in
    [jJyY]*) ;;
    *) echo "Nichts gespeichert."; exit 1 ;;
  esac
fi

if [ -z "$CHECK_ONLY" ]; then
  umask 077
  {
    echo "# Angelegt von einrichten. Diese Datei nie weitergeben oder einchecken."
    echo "AUXDATA_API_KEY=$KEY"
    [ "$BASE" = "$DEFAULT_BASE" ] || echo "AUXDATA_BASE_URL=$BASE"
  } > "$ENV_FILE"
  echo "Gespeichert in $ENV_FILE"
fi

# Welche Kurznamen aus models.json gibt es fuer diesen Schluessel?
if [ "$STATUS" = "200" ] && [ -f "$ROOT/models.json" ]; then
  echo
  echo "Kurznamen aus models.json:"
  sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1 \2/p' "$ROOT/models.json" | while read -r name target; do
    if grep -q "\"id\"[[:space:]]*:[[:space:]]*\"$target\"" "$BODY"; then
      printf '  \342\234\223 %-9s %s\n' "$name" "$target"
    else
      printf '  - %-9s %s  (nicht freigeschaltet)\n' "$name" "$target"
    fi
  done
fi

echo
echo "Weiter im Ordner deines Projekts:"
echo "  $ROOT/start-codex.sh"
echo "  $ROOT/start-claude.sh"
