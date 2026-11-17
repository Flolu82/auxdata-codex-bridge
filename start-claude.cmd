@echo off
rem Startet Claude Code mit einem Claude-Modell aus AuxData (ohne Bridge).
rem Aufruf: start-claude.cmd [modell] [weitere Claude-Code-Argumente]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-claude.ps1" %*
