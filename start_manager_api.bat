@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_manager_api.ps1" %*
set exit_code=%ERRORLEVEL%

endlocal & exit /b %exit_code%
