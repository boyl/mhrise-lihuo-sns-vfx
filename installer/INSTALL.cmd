@echo off
setlocal
for /f "delims=" %%P in ('where pwsh.exe 2^>nul') do set "LIHUO_PWSH=%%P" & goto :found
echo PowerShell 7 (pwsh.exe) was not found.
pause
exit /b 2
:found
"%LIHUO_PWSH%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
set "rc=%errorlevel%"
if not "%rc%"=="0" pause
exit /b %rc%
