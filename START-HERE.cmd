@echo off
setlocal
echo.
echo SWITCHGEAR 0.1.0
echo Windows setup for a separate Codex CLI / VS Code profile.
echo Existing Codex sign-ins are not copied or changed by the installer.
echo.
echo The installer will show its target paths and ask before changing anything.
call "%~dp0install-switchgear.cmd"
if errorlevel 1 goto install_failed
if not exist "%LOCALAPPDATA%\Programs\Switchgear\switchgear.cmd" goto install_failed
echo.
echo Starting profile setup. Review the paths before confirming.
call "%LOCALAPPDATA%\Programs\Switchgear\switchgear.cmd" setup
set "SWITCHGEAR_EXIT=%ERRORLEVEL%"
echo.
if not "%SWITCHGEAR_EXIT%"=="0" echo Setup did not complete. See the message above.
pause
exit /b %SWITCHGEAR_EXIT%
:install_failed
echo.
echo Installation did not complete. No profile setup was started.
pause
exit /b 1
