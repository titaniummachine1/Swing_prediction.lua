@echo off

echo [BundleAndDeploy] Running simple Lua bundler on src folder...
node simple-bundle.js

if %ERRORLEVEL% EQU 0 (
    echo [BundleAndDeploy] Copying bundled file to lua directory...
    if exist "build\Swing_prediction.lua" (
        copy /Y "build\Swing_prediction.lua" "%localappdata%\lua\Swing_prediction.lua"
        echo [BundleAndDeploy] Deployed to %localappdata%\lua\Swing_prediction.lua
    ) else (
        echo [BundleAndDeploy] ERROR: build\Swing_prediction.lua not found
    )
) else (
    echo [BundleAndDeploy] Bundle failed with error code %ERRORLEVEL%
)
exit /b %ERRORLEVEL%