# einrichten.ps1 - richtet den Zugang zu AuxData ein.
#
# Aufruf ueber einrichten.cmd:
#   einrichten.cmd             fragt den Schluessel ab, prueft ihn und schreibt .env
#   einrichten.cmd --pruefen   prueft nur den vorhandenen Schluessel, aendert nichts
#
# Der Schluessel wird verdeckt eingegeben, nie angezeigt und nur in die Datei
# .env neben diesem Skript geschrieben. Reines ASCII (Windows PowerShell 5.1).

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$EnvFile = Join-Path $Root '.env'
$DefaultBase = 'https://auxdata.ai'
$checkOnly = ($args.Count -gt 0 -and [string]$args[0] -eq '--pruefen')

function Fail($text) {
    Write-Host "FEHLER: $text"
    exit 1
}

# Liest eine Zeile. Laeuft das Skript nicht in einem Terminal (Eingabe
# umgeleitet), kommt die Zeile von der Standardeingabe.
function Read-Line($prompt, $hidden) {
    if ([Console]::IsInputRedirected) {
        Write-Host "${prompt}: " -NoNewline
        $line = [Console]::In.ReadLine()
        Write-Host ''
        if ($null -eq $line) { return '' }
        return $line.Trim()
    }
    if ($hidden) {
        $secure = Read-Host -Prompt $prompt -AsSecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr).Trim() }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    }
    return (Read-Host -Prompt $prompt).Trim()
}

function Read-EnvFile() {
    $values = @{}
    if (Test-Path $EnvFile) {
        foreach ($line in Get-Content -LiteralPath $EnvFile) {
            $t = $line.Trim()
            if (-not $t -or $t.StartsWith('#')) { continue }
            $i = $t.IndexOf('=')
            if ($i -lt 1) { continue }
            $values[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim().Trim('"').Trim("'")
        }
    }
    return $values
}

Write-Host ''
Write-Host 'AuxData-Zugang fuer Codex und Claude Code'
Write-Host '-----------------------------------------'

if ($checkOnly) {
    $stored = Read-EnvFile
    $key = $env:AUXDATA_API_KEY
    if (-not $key) { $key = $stored['AUXDATA_API_KEY'] }
    $base = $env:AUXDATA_BASE_URL
    if (-not $base) { $base = $stored['AUXDATA_BASE_URL'] }
    if (-not $base) { $base = $DefaultBase }
    if (-not $key) { Fail 'Kein Schluessel gefunden. Starte einrichten.cmd ohne --pruefen.' }
} else {
    if (Test-Path $EnvFile) {
        $answer = Read-Line 'Es gibt schon eine .env. Ueberschreiben? [j/N]' $false
        if ($answer -notmatch '^[jJyY]') {
            Write-Host 'Nichts geaendert. Mit "einrichten.cmd --pruefen" pruefst du den vorhandenen Schluessel.'
            exit 0
        }
    }
    Write-Host 'Den Schluessel erzeugst du in AuxData: Avatar-Menue -> Persoenliche Einstellungen'
    Write-Host '-> Karte "API-Schluessel" -> neuen Schluessel erzeugen. Er wird nur einmal angezeigt.'
    Write-Host ''
    $key = Read-Line 'Persoenlicher AuxData-Schluessel (Eingabe bleibt unsichtbar)' $true
    if (-not $key) { Fail 'Kein Schluessel eingegeben. Nichts gespeichert.' }
    if (-not $key.StartsWith('sk-auxdata-')) {
        Write-Host 'Hinweis: AuxData-Schluessel beginnen mit "sk-auxdata-". Ich pruefe ihn trotzdem.'
    }
    $base = Read-Line "Adresse deiner AuxData-Instanz [Enter = $DefaultBase]" $false
    if (-not $base) { $base = $DefaultBase }
}
$base = $base.TrimEnd('/')
if ($base -notmatch '^https?://') { Fail "Die Adresse muss mit https:// beginnen: $base" }

# Schluessel pruefen: Der Gateway nennt die Modelle, die er fuer diesen
# Schluessel fuehrt.
Write-Host ''
Write-Host "Pruefe den Schluessel an $base/v1/models ..."
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$ids = $null
$problem = ''
try {
    $response = Invoke-RestMethod -Uri "$base/v1/models" -Headers @{ Authorization = "Bearer $key" } -TimeoutSec 30
    $ids = @($response.data | ForEach-Object { [string]$_.id })
} catch {
    $status = 0
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
    if ($status -eq 401 -or $status -eq 403) {
        Fail "AuxData hat den Schluessel abgelehnt (Status $status). Nichts gespeichert. Erzeuge einen neuen Schluessel und versuch es noch einmal."
    }
    if ($status -gt 0) { $problem = "AuxData antwortet mit Status $status." }
    else { $problem = "Keine Verbindung zu ${base}: $($_.Exception.Message)" }
}

if ($problem) {
    Write-Host $problem
    if ($checkOnly) { exit 1 }
    $answer = Read-Line 'Der Schluessel ist nicht geprueft. Trotzdem speichern? [j/N]' $false
    if ($answer -notmatch '^[jJyY]') {
        Write-Host 'Nichts gespeichert.'
        exit 1
    }
} else {
    Write-Host "Der Schluessel gilt. Der Gateway fuehrt $($ids.Count) Modelle."
}

if (-not $checkOnly) {
    $text = "# Angelegt von einrichten. Diese Datei nie weitergeben oder einchecken.`nAUXDATA_API_KEY=$key`n"
    if ($base -ne $DefaultBase) { $text += "AUXDATA_BASE_URL=$base`n" }
    [IO.File]::WriteAllText($EnvFile, $text, (New-Object Text.UTF8Encoding($false)))
    Write-Host "Gespeichert in $EnvFile"
}

# Welche Kurznamen aus models.json gibt es fuer diesen Schluessel?
$modelsFile = Join-Path $Root 'models.json'
if ($ids -and (Test-Path $modelsFile)) {
    Write-Host ''
    Write-Host 'Kurznamen aus models.json:'
    $parsed = Get-Content -LiteralPath $modelsFile -Raw | ConvertFrom-Json
    foreach ($p in $parsed.aliases.PSObject.Properties) {
        if ($ids -contains [string]$p.Value) { $mark = '[ok]   ' } else { $mark = '[fehlt]' }
        $note = ''
        if ($mark -eq '[fehlt]') { $note = '  (nicht freigeschaltet)' }
        Write-Host ("  {0} {1,-9} {2}{3}" -f $mark, $p.Name, $p.Value, $note)
    }
}

Write-Host ''
Write-Host 'Weiter im Ordner deines Projekts:'
Write-Host "  $Root\start-codex.cmd"
Write-Host "  $Root\start-claude.cmd"
exit 0
