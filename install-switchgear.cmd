@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\Install-Switchgear.ps1" %*
exit /b %ERRORLEVEL%
