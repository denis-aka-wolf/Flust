@echo off
setlocal
set "SCRIPT_DIR=%~dp0"

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo ERROR: Windows PowerShell was not found.
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%setup_flust.ps1"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
    echo.
    echo Flust setup failed with exit code %RESULT%.
)
endlocal & exit /b %RESULT%
