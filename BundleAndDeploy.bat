@echo off
setlocal
cd /d "%~dp0"

echo [BundleAndDeploy] Running bundle and deploy...
node bundle-and-deploy.js
set "ERR=%ERRORLEVEL%"
if %ERR% NEQ 0 (
    echo [BundleAndDeploy] Failed with code %ERR%
    exit /b %ERR%
)
echo [BundleAndDeploy] Done.
exit /b 0
