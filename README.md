# auxdata-codex-bridge

Mit dieser kleinen Bridge arbeiten Codex und Claude Code mit den Modellen, die deine Organisation in AuxData freigeschaltet hat. Angemeldet wird mit deinem persönlichen AuxData-Schlüssel, der Verbrauch läuft über AuxData.

Die Bridge ist eine einzige Node-Datei ohne Pakete. Sie läuft nur auf deinem Rechner (127.0.0.1) und speichert keinen Schlüssel.

```
Codex        --Responses-->  Bridge  --Chat Completions-->  AuxData-Gateway  -->  Modell
Claude Code  --Messages--->  Bridge  --Messages---------->  AuxData-Gateway  -->  Modell
```

## Warum es die Bridge braucht

Der Gateway von AuxData spricht unter `/v1/chat/completions` das Format von OpenAI und unter `/v1/messages` das Format von Anthropic.

Codex spricht nur die Responses-API (`/v1/responses`). Die hat der Gateway nicht, am 17.11.2026 antwortete er dort mit 404. Die Bridge übersetzt deshalb in beide Richtungen, auch die Werkzeugaufrufe, mit denen Codex Dateien liest und Befehle ausführt.

Claude Code spricht das Anthropic-Format und käme mit dem Gateway eigentlich direkt zurecht. Ab Claude Opus 4.8 und bei allen 5er-Modellen schickt Claude Code aber in der Nachrichtenliste Einträge mit `role: "system"`, und die lehnt der Gateway ab: `API Error: 400 unsupported message role "system"`. Die Bridge reicht die Anfrage deshalb unverändert durch und hängt nur den Text solcher Einträge an die benachbarte Nutzernachricht. Antwort und Stream gehen so zurück, wie der Gateway sie liefert.

Mit Claude Sonnet 4.6 und Claude Haiku 4.5 tritt das nicht auf. Für diese beiden gibt es `--direkt`, ganz ohne Bridge und ohne Node.

## Was du brauchst

- einen Zugang zu AuxData mit einem persönlichen API-Schlüssel
- [Node.js](https://nodejs.org) ab Version 18
- Codex CLI oder Claude Code, je nachdem, womit du arbeiten willst

## Einrichten in drei Minuten

1. Schlüssel erzeugen. In AuxData: Avatar-Menü → Persönliche Einstellungen → Karte „API-Schlüssel“ → neuen Schlüssel erzeugen. Er beginnt mit `sk-auxdata-` und wird nur dieses eine Mal angezeigt.

2. Paket holen:

   ```bash
   git clone https://github.com/Flolu82/auxdata-codex-bridge.git
   ```

3. Einrichten starten. Windows: `einrichten.cmd` doppelklicken oder im Terminal aufrufen. macOS und Linux: `./einrichten.sh`. Meldet die Shell dort „Permission denied“, einmal `chmod +x *.sh` im Ordner ausführen.

Das Skript fragt den Schlüssel ab (die Eingabe bleibt unsichtbar) und die Adresse deiner AuxData-Instanz; mit Enter gilt `https://auxdata.ai`. Dann prüft es den Schlüssel am Gateway, schreibt ihn in die Datei `.env` neben den Skripten und zeigt, welche Kurznamen dein Schlüssel nutzen darf. Das sieht zum Beispiel so aus:

```
Der Schluessel gilt. Der Gateway fuehrt 178 Modelle.
Gespeichert in C:\tools\auxdata-codex-bridge\.env

Kurznamen aus models.json:
  [ok]    sonnet    anthropic/claude-sonnet-5-5
  [fehlt] opus      anthropic/claude-opus-5-5  (nicht freigeschaltet)
```

Lehnt AuxData den Schlüssel ab, wird nichts gespeichert. Eine vorhandene `.env` überschreibt das Skript nur nach Rückfrage. `einrichten.cmd --pruefen` prüft später den gespeicherten Schlüssel und zeigt die Liste noch einmal, ohne etwas zu ändern.

`.env` steht in `.gitignore`. Wer den Schlüssel lieber in einer Umgebungsvariable `AUXDATA_API_KEY` hält, braucht die Datei nicht; eine gesetzte Variable hat Vorrang. Von Hand geht es auch: `.env.example` nach `.env` kopieren und den Schlüssel eintragen.

## Codex starten

Du startest im Ordner deines Projekts. Windows:

```
C:\pfad\zu\auxdata-codex-bridge\start-codex.cmd
```

macOS und Linux:

```bash
/pfad/zu/auxdata-codex-bridge/start-codex.sh
```

Der Starter startet die Bridge im Hintergrund, falls sie noch nicht läuft, und ruft dann Codex mit dem Anbieter „AuxData“ auf. Deine `~/.codex/config.toml` ändert er nicht, die Einstellung gilt nur für diesen Aufruf.

Ein Aufruf ohne Dialog, zum Ausprobieren:

```
start-codex.cmd exec --skip-git-repo-check "Lies die Datei notiz.txt und nenne mir das Codewort."
```

Codex meldet dabei `warning: Model metadata for … not found. Defaulting to fallback metadata`. Das ist erwartet: Codex kennt die Modellnamen von AuxData nicht und rechnet mit Standardwerten für das Kontextfenster.

## Claude Code starten

Windows:

```
C:\pfad\zu\auxdata-codex-bridge\start-claude.cmd
```

macOS und Linux:

```bash
/pfad/zu/auxdata-codex-bridge/start-claude.sh
```

Der Starter setzt für diesen einen Aufruf die Umgebungsvariablen `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL` und die drei Modellplätze für Opus, Sonnet und Haiku. Deine Einstellungen unter `~/.claude` bleiben, wie sie sind; Hooks, Skills und MCP-Server gelten weiter.

Ohne Bridge, mit Sonnet 4.6 und Haiku 4.5:

```
start-claude.cmd --direkt
```

Claude Code zeigt beim Start eine Warnung, dass die Konnektoren von claude.ai abgeschaltet sind, weil eine andere Anmeldung Vorrang hat. Das stimmt und ist hier gewollt: In dieser Sitzung meldet sich Claude Code mit dem AuxData-Schlüssel an und nicht mit deinem Konto bei claude.ai.

## Modell wählen

Ohne Angabe nehmen beide Starter `anthropic/claude-sonnet-5-5`. Ein anderes Modell nennst du als erstes Argument, entweder als Kurzname aus `models.json` oder mit der vollen Kennung des Gateways:

```
start-codex.cmd opus
start-claude.cmd fable
start-codex.cmd mistral/mistral-medium-3-5 exec "…"
```

| Kurzname | Kennung am Gateway | Anbieter und Standort laut Modell-Liste in AuxData |
|---|---|---|
| `fable` | `anthropic/claude-fable-5-2` | Anthropic, USA |
| `opus` | `anthropic/claude-opus-5-5` | Anthropic, USA |
| `sonnet` | `anthropic/claude-sonnet-5-5` | Anthropic, USA |
| `haiku` | `anthropic/claude-haiku-5-5` | Anthropic, USA |
| `mistral` | `mistral/mistral-medium-3-5` | Mistral, Frankreich (EU) |
| `devstral` | `mistral/devstral-latest` | Mistral, Frankreich (EU) |
| `glm` | `mistral/zai-glm-5-3` | Mistral, Frankreich (EU) |
| `deepseek` | `mistral/deepseek-v4-1-flash-1017` | Mistral, Frankreich (EU) |
| `qwen` | `openhippo/openhippo/Qwen3.8-27B` | OpenHippo, Deutschland |
| `qwen-ionos` | `ionos/Qwen/Qwen3.8-27B` | IONOS, Deutschland |

Die Standorte stammen aus der Modell-Liste einer AuxData-Organisation vom 17.11.2026. Maßgeblich ist, was eure Administration unter „Verfügbare LLM's“ sieht und freigibt.

### Mit Modellen aus der EU arbeiten

Du bist nicht auf die Claude-Modelle angewiesen. Codex und Claude Code laufen über die Bridge auch mit Modellen, die AuxData bei Anbietern in Frankreich und Deutschland führt, zum Beispiel von Mistral, OpenHippo und IONOS:

```
start-claude.cmd devstral
start-codex.cmd qwen
start-codex.cmd openhippo/tensorx/glm-5.3-flash
```

Dann geht dein Quelltext an keinen Anbieter in den USA. Ob das für euren Fall genügt, entscheidet euer Datenschutz, nicht dieses Paket: Dazu gehören auch der Vertrag mit AuxData und die Frage, was Codex oder Claude Code selbst an ihre Hersteller melden.

Eigene Kurznamen trägst du in `models.json` ein. Welche Modelle es bei dir gibt, zeigt `einrichten --pruefen` für die Kurznamen und der Gateway unter `/v1/models` für alle; die Bridge reicht die Liste durch (`GET http://127.0.0.1:8790/v1/models` mit deinem Schlüssel als Bearer). Die Kennung besteht immer aus Anbieter, Schrägstrich und Modell. Ohne den Anbieter davor antwortet der Gateway mit 404 „Model not found or not permitted“.

Claude Code läuft auch mit Modellen, die nicht von Anthropic stammen, hier etwa `mistral`, `devstral`, `glm`, `deepseek` und `qwen`. Es meldet dann `Claude Code doesn't recognize the model …, so it assumes a context window of 1m tokens`. Das Kontextfenster dieser Modelle ist kleiner; bei langen Sitzungen kann eine Anfrage deshalb zu groß werden.

Claude Code kennt neben dem Modell der Sitzung drei Plätze: Opus, Sonnet und Haiku. Welche Kennung hinter jedem Platz liegt, steht in `models.json`; der Starter übergibt sie als `ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL` und `ANTHROPIC_DEFAULT_HAIKU_MODEL`.

## Schlüssel, Kosten, Datenschutz

Codex und Claude Code schicken den Schlüssel mit jeder Anfrage als `Authorization: Bearer …`. Die Bridge gibt den Header an den Gateway weiter. Sie speichert ihn nicht, schreibt ihn in kein Protokoll und bekommt ihn auch nicht in ihre Umgebung. Sie nimmt nur Verbindungen vom eigenen Rechner an.

Der Schlüssel ist an dich gebunden. Jede Anfrage zählt in AuxData als dein Verbrauch, Budgets und Limits deiner Organisation gelten. Ein Coding-Agent verbraucht deutlich mehr als ein Chat: Bei Codex 0.169.0 hatte schon die erste Anfrage eines Laufs je nach Modell rund 19.000 bis 26.000 Eingabetokens, weil Anweisungen und Werkzeugbeschreibungen jedes Mal mitgehen.

Alles, was Codex oder Claude Code dem Modell schicken, geht über AuxData an den Anbieter des gewählten Modells: deine Eingaben, Inhalte von Dateien, die der Agent liest, Ausgaben von Befehlen. Klär vorher, welche Modelle du für welchen Code nehmen darfst. Was Codex und Claude Code von sich aus an ihre Hersteller melden, regelt die Bridge nicht. `start-claude` schaltet bei Claude Code Telemetrie, Fehlerberichte und die Update-Prüfung ab (`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`).

## Wenn etwas hakt

| Was du siehst | Ursache | Was hilft |
|---|---|---|
| `FEHLER: AUXDATA_API_KEY fehlt` | weder `.env` noch Umgebungsvariable | `einrichten` starten |
| Codex: fünfmal `Reconnecting...`, dann `401 Unauthorized: AuxData gateway: Invalid API key` | Schlüssel falsch oder widerrufen | neuen Schlüssel in AuxData erzeugen, `einrichten` noch einmal starten |
| `404 … Model not found or not permitted` | Kennung falsch geschrieben, Anbieter davor vergessen, oder das Modell ist für dich nicht freigeschaltet | `einrichten --pruefen` zeigt, welche Kurznamen gehen |
| `429` | Rate Limit oder Token-Limit in AuxData erreicht | warten, Limit mit der Administration klären |
| Claude Code: `API Error: 400 unsupported message role "system"` | neueres Claude-Modell direkt am Gateway, ohne Bridge | `start-claude` ohne `--direkt` nehmen |
| `Port 8790 ist von einem anderen Programm belegt` | ein anderes Programm nutzt den Port | `BRIDGE_PORT=8791` in `.env` |
| `Die Bridge ist nicht gestartet` | Node fehlt oder ist älter als 18, oder die Bridge bricht beim Start ab | `node --version` prüfen, in `bridge.log` nachsehen |
| `502 AuxData gateway unreachable` | keine Verbindung zu AuxData, falsche `AUXDATA_BASE_URL`, oder keine Antwort binnen 300 Sekunden | Netz und Adresse prüfen |

Die Bridge schreibt je Anfrage eine Zeile nach `bridge.log`, mit Uhrzeit, Modell, Status, Dauer und bei Codex den Tokens. Inhalte und Schlüssel stehen nicht darin:

```
09:29:03 POST /v1/responses anthropic/claude-sonnet-5-5 -> 200 in 1.4 s (25974 Tokens rein, 60 raus, 1 Werkzeugaufruf)
09:28:31 POST /v1/messages anthropic/claude-sonnet-5-5 -> 200 in 1.7 s, 1 system-Nachricht umgesetzt
```

Mit `BRIDGE_DEBUG=1` kommt je Codex-Anfrage eine Zeile dazu, welche Arten von Werkzeugen Codex mitschickt.

## Bridge von Hand bedienen

```
node bridge.js            im Vordergrund starten, Protokoll im Terminal
node bridge.js --start    im Hintergrund starten, falls sie nicht läuft
node bridge.js --stop     die laufende Bridge beenden
```

Die Bridge läuft nach dem Ende von Codex oder Claude Code weiter, bis du sie beendest oder den Rechner neu startest. `http://127.0.0.1:8790/health` zeigt, ob sie läuft.

Wer die Starter nicht nutzen will, trägt den Anbieter selbst ein. Für Codex in `~/.codex/config.toml`:

```toml
[model_providers.auxdata]
name = "AuxData"
base_url = "http://127.0.0.1:8790/v1"
env_key = "AUXDATA_API_KEY"
wire_api = "responses"
```

und startet mit `codex -c model_provider=auxdata -m anthropic/claude-sonnet-5-5`. Für Claude Code reichen die Umgebungsvariablen aus `start-claude.sh`.

## Grenzen

- Die Bridge ruft den Gateway für Codex ohne Streaming auf. Codex zeigt eine Antwort deshalb erst, wenn sie fertig ist. Bei Claude Code wird der Stream durchgereicht.
- Die Websuche von Codex läuft bei OpenAI auf dem Server und fehlt über AuxData. Die ChatGPT-Apps schaltet der Starter ab (`--disable apps`); sie brauchen eine Anmeldung bei OpenAI und würden jede Anfrage um rund 20.000 Tokens vergrößern.
- Die Denkstufe von Codex (`reasoning effort`) gibt die Bridge nicht an den Gateway weiter.
- `POST /v1/messages/count_tokens` gibt es am Gateway nicht (404). Claude Code arbeitet trotzdem.
- Bilder an Codex und Freiform-Werkzeuge übersetzt die Bridge, das ist aber nur mit den mitgelieferten Tests geprüft und nicht in einem echten Lauf.
- Für Gemini 4 Argon schickt die Bridge frühere Werkzeugaufrufe als Text mit, weil der Gateway eine von Google verlangte Signatur nicht durchreicht. Das stammt aus einer Vorgängerversion und ist mit dieser Fassung nicht erneut geprüft.

## Geprüft

Stand 17.11.2026, Windows 11, Node 24, Codex CLI 0.169.0, Claude Code 2.1.326, gegen `https://auxdata.ai`:

- Codex über die Bridge mit `anthropic/claude-sonnet-5-5`, `anthropic/claude-haiku-5-5`, `anthropic/claude-haiku-4-5`, `mistral/mistral-medium-3-5`, `mistral/devstral-latest`, `mistral/zai-glm-5-3`, `mistral/deepseek-v4-1-flash-1017`, `openhippo/openhippo/Qwen3.8-27B`, `openhippo/tensorx/glm-5.3-flash`, `openhippo/aki-io/deepseek-v4.1-flash-552b` und `ionos/Qwen/Qwen3.8-27B`: Datei lesen; mit Haiku 4.5 auch Datei anlegen.
- Claude Code über die Bridge mit Sonnet 5.5, Haiku 5.5, Mistral Medium 3.5, Devstral, GLM 5.3, DeepSeek V4.1 Flash, mit Qwen 3.8 27B, GLM 5.3 Flash und DeepSeek V4.1 Flash von OpenHippo und mit Qwen 3.8 27B von IONOS: Datei lesen. Opus 5.5 und Fable 5.2: kurze Antwort.
- Das sind kurze Läufe mit einem Werkzeugaufruf. Wie gut ein Modell eine längere Aufgabe an echtem Quelltext löst, zeigen sie nicht.
- Claude Code mit `--direkt` (Sonnet 4.6): Datei lesen.
- `einrichten` in beiden Fassungen: Schlüssel prüfen, `.env` anlegen, Rückfrage vor dem Überschreiben, abgelehnter Schlüssel.
- Die `.sh`-Starter sind unter Git Bash auf Windows gelaufen, auf macOS und Linux bisher nicht.
- Geprüft sind Aufrufe ohne Dialog (`codex exec …`, `claude -p …`). Längere Dialogsitzungen und der Wechsel mit `/model` sind mit dieser Fassung nicht durchgespielt.

Die Tests laufen ohne Netz:

```bash
node --test
```

## Erweitern und aktualisieren

Das Paket ist dafür gedacht, dass du es anpasst.

- Neue Modelle: einen Kurznamen in `models.json` eintragen, `einrichten --pruefen` zeigt, ob dein Schlüssel das Modell nutzen darf. Ändert AuxData eine Kennung oder kommt ein neues Modell dazu, reicht diese eine Zeile.
- Standardmodell: bei `start-codex` die Zeile `DefaultModel` bzw. `DEFAULT_MODEL` oben im Startskript; `start-claude` nimmt, was in `models.json` hinter `sonnet` steht.
- Neue Fassung holen: `git pull` im Ordner der Bridge, danach `node bridge.js --stop`; der nächste Start nimmt die neue Fassung. Deine `.env` bleibt unberührt.
- Verhalten ändern: Die Bridge ist eine Datei. Die Übersetzung für Codex und der Durchreicher für Claude Code sind eigene Abschnitte, und `node --test` prüft beide ohne Netz. Wer ein weiteres Werkzeug anbinden will, das eine dieser beiden Schnittstellen spricht, braucht meist nur ein weiteres Startskript.
- Wenn AuxData eine der beiden Lücken schließt (`/v1/responses`, Systemnachrichten in `/v1/messages`), wird der zugehörige Teil der Bridge überflüssig. `start-claude --direkt` zeigt, wie der Aufruf ohne Bridge aussieht.

## Lizenz

MIT, siehe [LICENSE](LICENSE). Die Bridge ist kein Produkt von AuxData, OpenAI oder Anthropic.
