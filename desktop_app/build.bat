@echo off
echo ========================================
echo Al-Mudeer Desktop App - Build Script
echo ========================================
echo.

cd /d "%~dp0"

echo Step 1: Getting dependencies...
call flutter pub get
if errorlevel 1 (
    echo.
    echo ERROR: Failed to get dependencies!
    echo Try running: flutter clean
    pause
    exit /b 1
)

echo.
echo Step 2: Analyzing code...
call flutter analyze
if errorlevel 1 (
    echo.
    echo WARNING: Code analysis found issues!
    echo Continue anyway? (Y/N)
    set /p continue=
    if /i not "%continue%"=="Y" exit /b 1
)

echo.
echo Step 3: Building Windows release...
call flutter build windows --release
if errorlevel 1 (
    echo.
    echo ERROR: Build failed!
    pause
    exit /b 1
)

echo.
echo ========================================
echo Build completed successfully!
echo Output: build\windows\x64\runner\Release\
echo ========================================
echo.
pause
