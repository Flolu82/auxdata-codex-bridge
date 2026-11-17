# start-claude.ps1 - startet Claude Code mit einem Claude-Modell aus AuxData.
#
# Aufruf ueber start-claude.cmd:
#   start-claude.cmd                 Standardmodell (Sonnet), interaktiv
#   start-claude.cmd opus            Kurzname aus models.json
#   start-claude.cmd anthropic/claude-fable-5-2 -p "Frage"
#   start-claude.cmd -p "Frage"      Standardmodell, weitere Claude-Code-Argumente
#   start-claude.cmd --direkt        ohne Bridge, mit Sonnet 4.6 und Haiku 4.5
#
# Der AuxData-Gateway hat einen eigenen Endpunkt im Anthropic-Format
# (/v1/messages). Claude Code schickt aber ab Opus 4.8 und bei allen
# 5er-Modellen Nachrichten mit role "system", die der Gateway ablehnt. Deshalb
# laeuft Claude Code hier ueber die lokale Bridge, die nur diese Nachrichten
# umsetzt. Mit --direkt geht es ohne Bridge und ohne Node, dann aber nur mit
# aelteren Modellen.
#
# Reines ASCII, kein param()-Block (sonst wuerde -p nicht bei Claude Code ankommen).

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot

# Modelle fuer --direkt: die neuesten, die Claude Code ohne Bridge annimmt.
$DirectSonnet = 'anthropic/claude-sonnet-4-6'
$DirectHaiku = 'anthropic/claude-haiku-4-5'

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
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Fail "Claude Code nicht gefunden (Befehl 'claude')." }

$rest = @($args)
$direct = $false
if ($rest.Count -gt 0 -and [string]$rest[0] -eq '--direkt') {
    $direct = $true
    $rest = @($rest | Select-Object -Skip 1)
}

# Kurznamen aus models.json (fable, opus, sonnet, haiku ...).
$aliases = @{}
$modelsFile = Join-Path $Root 'models.json'
if (Test-Path $modelsFile) {
    $parsed = Get-Content -LiteralPath $modelsFile -Raw | ConvertFrom-Json
    foreach ($p in $parsed.aliases.PSObject.Properties) { $aliases[$p.Name] = [string]$p.Value }
}
function Alias-Or($name, $fallback) {
    if ($aliases.ContainsKey($name)) { return $aliases[$name] }
    return $fallback
}

$base = 'https://auxdata.ai'
if ($env:AUXDATA_BASE_URL) { $base = $env:AUXDATA_BASE_URL.TrimEnd('/') }

if ($direct) {
    $opus = $DirectSonnet
    $sonnet = $DirectSonnet
    $haiku = $DirectHaiku
    $model = $DirectSonnet
} else {
    $opus = Alias-Or 'opus' 'anthropic/claude-opus-5-5'
    $sonnet = Alias-Or 'sonnet' 'anthropic/claude-sonnet-5-5'
    $haiku = Alias-Or 'haiku' 'anthropic/claude-haiku-5-5'
    $model = $sonnet
    # Erstes Argument ist das Modell, wenn es ein Kurzname oder eine Gateway-ID ist.
    if ($rest.Count -gt 0) {
        $first = [string]$rest[0]
        if ($aliases.ContainsKey($first)) {
            $model = $aliases[$first]
            $rest = @($rest | Select-Object -Skip 1)
        } elseif ($first -match '^[A-Za-z0-9_.-]+/[A-Za-z0-9_./:-]+$') {
            $model = $first
            $rest = @($rest | Select-Object -Skip 1)
        }
    }
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Fail "Node.js (ab Version 18) nicht gefunden. Ohne Node geht nur 'start-claude.cmd --direkt'."
    }
    if (-not $env:BRIDGE_PORT) { $env:BRIDGE_PORT = '8790' }
    & node (Join-Path $Root 'bridge.js') --start
    if ($LASTEXITCODE -ne 0) { exit 1 }
    # 127.0.0.1 statt localhost: die Bridge bindet nur IPv4.
    $base = "http://127.0.0.1:$($env:BRIDGE_PORT)"
}

# Adresse ohne /v1: Claude Code haengt /v1/messages selbst an.
$env:ANTHROPIC_BASE_URL = $base
# Der Schluessel geht als "Authorization: Bearer ..." an den Gateway.
$env:ANTHROPIC_AUTH_TOKEN = $env:AUXDATA_API_KEY
# Ein zusaetzlich gesetzter ANTHROPIC_API_KEY wuerde mit dem Token konkurrieren.
if (Test-Path Env:ANTHROPIC_API_KEY) { Remove-Item Env:ANTHROPIC_API_KEY }
# Der Gateway kennt die Modelle nur mit dem Praefix "anthropic/".
$env:ANTHROPIC_MODEL = $model
$env:ANTHROPIC_DEFAULT_OPUS_MODEL = $opus
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $sonnet
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $haiku
# Keine Telemetrie, Fehlerberichte und Update-Pruefungen an Anthropic.
$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'

Say "-> Claude Code mit AuxData, Modell $model ($base)"
& claude @rest
exit $LASTEXITCODE
