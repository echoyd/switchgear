@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0core\Switchgear.ps1" %*
exit /b %ERRORLEVEL%
