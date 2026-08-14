@echo off
REM Mehd AI — Production Flutter Build Script (Security Hardened)
REM Enforces Dart source obfuscation and debug symbol splitting to protect IP.

echo ===================================================
echo   Building Mehd AI Flutter App (Production Mode)
echo ===================================================

mkdir build\app\outputs\symbols 2>nul

flutter build apk --release ^
  --obfuscate ^
  --split-debug-info=build/app/outputs/symbols ^
  --target-platform android-arm,android-arm64,android-x64

if %ERRORLEVEL% EQU 0 (
    echo.
    echo [SUCCESS] Release APK built with Dart Obfuscation enabled.
    echo Symbol map saved to: build/app/outputs/symbols/
    echo KEEP SYMBOL MAP SECRET -- DO NOT SHIP SYMBOLS WITH THE APK!
) else (
    echo.
    echo [ERROR] Build failed. Check errors above.
)
