@echo off
setlocal
cd /d "%~dp0"
if "%~1"=="" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0restore-opencode-layout.ps1"
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0restore-opencode-layout.ps1" -OpenCodePath "%~1"
)
echo.
pause
