@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FlattenManualColoursAboveFirstLayer.ps1" %*
exit /b %ERRORLEVEL%
