@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VERIFY-OBS-MEETING-PORTABILITY.ps1"
set "RC=%ERRORLEVEL%"
echo.
echo A diagnostic report was saved in the Verification folder.
pause
exit /b %RC%
