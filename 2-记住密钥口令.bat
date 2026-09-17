@echo off
setlocal
title Claude Trans
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0remember-key.ps1"
pause
