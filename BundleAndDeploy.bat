@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "TITLEFILE=title.txt"
set "DEPLOY_ROOT=%localappdata%"
if "%DEPLOY_ROOT%"=="" (
  echo [BundleAndDeploy] LOCALAPPDATA is not set. Cannot deploy.
  exit /b 1
)
set "DEPLOY_DIR=%DEPLOY_ROOT%\lua"

if not exist "%DEPLOY_ROOT%" (
  echo [BundleAndDeploy] Creating %DEPLOY_ROOT%
  mkdir "%DEPLOY_ROOT%"
)
if not exist "%DEPLOY_DIR%" (
  echo [BundleAndDeploy] Creating %DEPLOY_DIR%
  mkdir "%DEPLOY_DIR%"
)

set "BUILD_DIR=%SCRIPT_DIR%build"

rem Ensure build directory exists
if not exist "%BUILD_DIR%\" mkdir "%BUILD_DIR%"

rem Determine actual output file name from title.txt or default
set "OUTFILE=Swing_prediction.lua"
if exist "%SCRIPT_DIR%%TITLEFILE%" (
  set /p OUTFILE=<"%SCRIPT_DIR%%TITLEFILE%"
)
if "%OUTFILE%"=="" set "OUTFILE=Swing_prediction.lua"

set "BUNDLE_PATH=%BUILD_DIR%\%OUTFILE%"
set "DEPLOY_PATH=%DEPLOY_DIR%\%OUTFILE%"

rem Run luabundler on src folder
echo [BundleAndDeploy] Running luabundler on src folder...
luabundler bundle "src/Main.lua" -p "src/?.lua" -p "?.lua" -o "%BUNDLE_PATH%"
if errorlevel 1 (
  echo [BundleAndDeploy] Luabundler failed. Ensure luabundler is installed and in PATH.
  exit /b 1
)

rem Wait for bundle to be created
set "_BUNDLE_READY="
for /L %%I in (1,1,20) do (
  if exist "%BUNDLE_PATH%" (
    for %%F in ("%BUNDLE_PATH%") do if %%~zF GTR 0 set "_BUNDLE_READY=1"
  )
  if defined _BUNDLE_READY goto :bundle_ready
  timeout /T 1 >nul
)

echo [BundleAndDeploy] Bundle "%BUNDLE_PATH%" not ready after waiting.
exit /b 1

:bundle_ready

if /I "%BUNDLE_PATH%"=="%DEPLOY_PATH%" (
  echo [BundleAndDeploy] Bundle already located at %DEPLOY_PATH%
) else (
  copy /Y "%BUNDLE_PATH%" "%DEPLOY_PATH%" >nul
  if errorlevel 1 (
    echo [BundleAndDeploy] Deployment failed. Ensure %DEPLOY_DIR% is writable.
    exit /b 1
  )
)

echo [BundleAndDeploy] Deployed to %DEPLOY_PATH%

endlocal
exit /b 0
