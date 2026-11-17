@echo off
rem Startet Codex mit einem Modell aus AuxData (ueber die lokale Bridge).
rem Aufruf: start-codex.cmd [modell] [weitere Codex-Argumente]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-codex.ps1" %*
