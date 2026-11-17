# start-codex.ps1 - startet Codex mit einem Modell aus AuxData.
#
# Aufruf ueber start-codex.cmd:
#   start-codex.cmd                         Standardmodell, interaktiv
#   start-codex.cmd opus                    Kurzname aus models.json
#   start-codex.cmd mistral/mistral-medium-3-5 exec "Frage"
#   start-codex.cmd exec "Frage"            Standardmodell, weitere Codex-Argumente
#
# Diese Datei ist bewusst reines ASCII und hat keinen param()-Block:
# Windows PowerShell 5.1 liest Skripte ohne BOM als ANSI, und ein param()-Block
# wuerde Codex-Argumente wie -m oder -p an sich ziehen.

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$DefaultModel = 'anthropic/claude-sonnet-5-5'

# Meldungen des Starters gehen nach stderr, damit die Ausgabe des Programms
# (zum Beispiel JSON bei -p) sauber bleibt.
function Say($text) { [Console]::Error.WriteLine($text) }
function Fail($text) {
    Say "FEHLER: $text"
    exit 1
}

# .env neben dem Skript lesen. Werte gelten nur fuer diesen Prozess;
# bereits gesetzte Umgebungsvariablen haben Vorrang.
$envFile = Join-Path $Root '.env'
if (Test-Path $envFile) {
    foreach ($line in Get-Content -LiteralPath $envFile) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 1) { continue }
        $name = $t.Substring(0, $i).Trim()
        $value = $t.Substring($i + 1).Trim().Trim('"').Trim("'")
        if ($value -and -not (Test-Path "Env:$name")) { Set-Item -Path "Env:$name" -Value $value }
    }
}

if (-not $env:AUXDATA_API_KEY) {
    Fail "AUXDATA_API_KEY fehlt. Kopiere .env.example nach .env und trage deinen persoenlichen AuxData-Schluessel ein."
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Fail "Node.js (ab Version 18) nicht gefunden." }
if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { Fail "Codex CLI nicht gefunden (Befehl 'codex')." }

$bridgeJs = Join-Path $Root 'bridge.js'
if (-not $env:BRIDGE_PORT) { $env:BRIDGE_PORT = '8790' }
# 127.0.0.1 statt localhost: die Bridge bindet nur IPv4.
$bridgeUrl = "http://127.0.0.1:$($env:BRIDGE_PORT)"

# Erstes Argument ist das Modell, wenn es eine Gateway-ID (mit Schraegstrich)
# oder ein Kurzname aus models.json ist. Sonst gilt das Standardmodell.
$model = $DefaultModel
$rest = @($args)
if ($args.Count -gt 0) {
    $first = [string]$args[0]
    $resolved = ''
    if ($first -match '^[A-Za-z0-9_.-]+/[A-Za-z0-9_./:-]+$') { $resolved = $first }
    elseif ($first -match '^[A-Za-z0-9_.-]+$') { $resolved = [string](& node $bridgeJs --resolve $first) }
    if ($resolved) {
        $model = $resolved.Trim()
        $rest = @($args | Select-Object -Skip 1)
    }
}

# Bridge starten, falls sie noch nicht laeuft. Sie bekommt den Schluessel nicht
# in ihre Umgebung; er kommt mit jeder Anfrage von Codex.
& node $bridgeJs --start
if ($LASTEXITCODE -ne 0) { exit 1 }

Say "-> Codex mit AuxData, Modell $model (Bridge $bridgeUrl)"

# Der Provider wird nur fuer diesen Aufruf gesetzt; ~/.codex/config.toml bleibt
# unveraendert. wire_api muss "responses" sein. "apps" sind die ChatGPT-Apps von
# OpenAI: ohne OpenAI-Anmeldung nutzlos, sie wuerden nur jede Anfrage vergroessern.
& codex --disable apps `
    -c model_provider=auxdata `
    -c model_providers.auxdata.name=AuxData `
    -c "model_providers.auxdata.base_url=$bridgeUrl/v1" `
    -c model_providers.auxdata.env_key=AUXDATA_API_KEY `
    -c model_providers.auxdata.wire_api=responses `
    -m $model @rest
exit $LASTEXITCODE
