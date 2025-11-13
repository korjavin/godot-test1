@echo off
REM
REM Local Web Server for Godot Game (Windows)
REM
REM This script starts a local HTTP server to test the web build.
REM

setlocal enabledelayedexpansion

REM Configuration
set PORT=8000
set BUILD_DIR=build\web
set DOWNLOAD_DIR=web-build

echo ========================================
echo   Godot Web Game Local Server
echo ========================================
echo.

REM Find web directory
if exist "%BUILD_DIR%" (
    set WEB_DIR=%BUILD_DIR%
) else if exist "%DOWNLOAD_DIR%" (
    set WEB_DIR=%DOWNLOAD_DIR%
) else (
    echo [ERROR] No web build found!
    echo.
    echo Please build the game first:
    echo   1. Open Godot
    echo   2. Go to Project - Export
    echo   3. Select 'Web' preset
    echo   4. Click 'Export Project'
    echo.
    echo Or download the web-build artifact from GitHub Actions
    echo and extract it to .\web-build\
    pause
    exit /b 1
)

echo [OK] Found web build in: %WEB_DIR%
echo.

REM Check if index.html exists
if not exist "%WEB_DIR%\index.html" (
    echo [ERROR] index.html not found in %WEB_DIR%
    pause
    exit /b 1
)

REM Check for Python
where python >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Python not found!
    echo Please install Python 3 to run the local server.
    echo Download from: https://www.python.org/downloads/
    echo.
    pause
    exit /b 1
)

echo [OK] Python found
echo.
echo ========================================
echo Server is running!
echo ========================================
echo.
echo   Local:    http://localhost:%PORT%
echo.
echo Instructions:
echo   1. Open your browser
echo   2. Navigate to: http://localhost:%PORT%
echo   3. Wait for the game to load
echo.
echo To stop the server: Press Ctrl+C
echo.
echo ========================================
echo.

REM Try to open browser
start http://localhost:%PORT%

REM Start server
cd "%WEB_DIR%"
python -m http.server %PORT%

pause
