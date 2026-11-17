@echo off
rem Richtet den Zugang zu AuxData ein: fragt den Schluessel ab, prueft ihn, schreibt .env.
rem Aufruf: einrichten.cmd [--pruefen]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0einrichten.ps1" %*
