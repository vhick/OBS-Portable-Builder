@echo off
setlocal
cd /d "%~dp0bin\64bit"
if not exist "%CD%\obs64.exe" (
  echo ERROR: OBS binary not found. Extract the entire GitHub ZIP first.
  pause
  exit /b 1
)
start "" "%CD%\obs64.exe" --portable --disable-updater
