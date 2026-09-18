@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "SWITCHGEAR_UNINSTALL_BOOTSTRAP=%TEMP%\switchgear-uninstall-%RANDOM%-%RANDOM%"
if exist "%SWITCHGEAR_UNINSTALL_BOOTSTRAP%" (
    echo FAIL - temporary uninstall bootstrap already exists.
    exit /b 1
)
mkdir "%SWITCHGEAR_UNINSTALL_BOOTSTRAP%\installer" >nul 2>&1
if errorlevel 1 (
    echo FAIL - unable to create temporary uninstall bootstrap.
    exit /b 1
)
xcopy "%~dp0installer\*" "%SWITCHGEAR_UNINSTALL_BOOTSTRAP%\installer\" /E /I /Q /Y >nul
if errorlevel 1 (
    echo FAIL - unable to copy temporary uninstall bootstrap.
    exit /b 1
)
(
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SWITCHGEAR_UNINSTALL_BOOTSTRAP%\installer\Uninstall-Switchgear.ps1" -CommandWrapper -BootstrapDirectory "%SWITCHGEAR_UNINSTALL_BOOTSTRAP%" %*
    set "switchgear_exit=!ERRORLEVEL!"
    if not "!switchgear_exit!"=="0" exit /b !switchgear_exit!
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SWITCHGEAR_UNINSTALL_BOOTSTRAP%\installer\Schedule-UninstallCleanup.ps1" -BootstrapDirectory "%SWITCHGEAR_UNINSTALL_BOOTSTRAP%" >nul
    set "switchgear_schedule_exit=!ERRORLEVEL!"
    if not "!switchgear_schedule_exit!"=="0" exit /b !switchgear_schedule_exit!
    exit /b !switchgear_exit!
)
