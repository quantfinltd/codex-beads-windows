@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "POWERSHELL_LAUNCHER=%SCRIPT_DIR%launch_bead_codex.ps1"

if not exist "%POWERSHELL_LAUNCHER%" (
    >&2 echo ERROR: Missing PowerShell launcher: "%POWERSHELL_LAUNCHER%"
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%POWERSHELL_LAUNCHER%" %*
exit /b %ERRORLEVEL%