@echo off
setlocal enabledelayedexpansion

call :main
echo.
pause
exit /b

:main
echo ============================================
echo   CS-INV-MQTT Service Launcher
echo ============================================
echo.

REM --- Get local IP ---
set LOCAL_IP=localhost
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do (
    set LOCAL_IP=%%a
    set LOCAL_IP=!LOCAL_IP: =!
    goto :ip_found
)
:ip_found
echo Local IP: %LOCAL_IP%
echo.

REM ========== [1] Stop old services ==========
echo [1/7] Stopping old services...
taskkill /F /IM inv_device_server.exe >nul 2>&1
taskkill /F /IM inv-device-server.exe >nul 2>&1
taskkill /F /IM inv_api_server.exe >nul 2>&1
taskkill /F /IM inv-api-server.exe >nul 2>&1
taskkill /F /IM main.exe >nul 2>&1
timeout /t 2 /nobreak >nul
echo Done.
echo.

REM ========== [2] Check PostgreSQL ==========
echo [2/7] Checking PostgreSQL (5432)...
netstat -ano | findstr ":5432.*LISTENING" >nul 2>&1
if errorlevel 1 (
    echo   [WARN] PostgreSQL is NOT running!
) else (
    echo   PostgreSQL is running.
)
echo.

REM ========== [3] Check Redis ==========
echo [3/7] Checking Redis (6379)...
netstat -ano | findstr ":6379.*LISTENING" >nul 2>&1
if errorlevel 1 (
    echo   [WARN] Redis is NOT running!
) else (
    echo   Redis is running.
)
echo.

REM ========== [4] Start inv_device_server ==========
echo [4/7] Starting inv_device_server (8081)...
if exist "d:\INV-MQTT\inv_device_server\inv_device_server.exe" (
    start "Device-Server" /min /d "d:\INV-MQTT\inv_device_server" cmd /c "inv_device_server.exe -config config.yaml"
    echo   Device Server started.
) else (
    echo   [ERROR] inv_device_server.exe not found!
)
echo.

REM ========== [5] Start inv_api_server ==========
echo [5/7] Starting inv_api_server (8080)...
if exist "d:\INV-MQTT\inv_api_server\inv-api-server.exe" (
    start "API-Server" /min /d "d:\INV-MQTT\inv_api_server" cmd /c "inv-api-server.exe -config config.yaml"
    echo   API Server started.
) else if exist "d:\INV-MQTT\inv_api_server\inv_api_server.exe" (
    start "API-Server" /min /d "d:\INV-MQTT\inv_api_server" cmd /c "inv_api_server.exe -config config.yaml"
    echo   API Server started.
) else (
    echo   [ERROR] API Server exe not found!
)
echo.

REM ========== [6] Start NestJS Admin Backend ==========
echo [6/7] Starting NestJS Admin Backend (3000)...
if exist "d:\INV-MQTT\inv-admin-backend\package.json" (
    start "NestJS-Admin" /min cmd /c "cd /d d:\INV-MQTT\inv-admin-backend && npm run start:dev"
    echo   NestJS Admin Backend starting...
) else (
    echo   [WARN] inv-admin-backend not found.
)
echo.

REM ========== [7] Start Admin Frontend ==========
echo [7/7] Starting Admin Frontend (5173)...
if exist "d:\INV-MQTT\inv-admin-frontend\package.json" (
    start "Admin-Frontend" /min cmd /c "cd /d d:\INV-MQTT\inv-admin-frontend && npm run dev"
    echo   Admin Frontend starting...
) else (
    echo   [WARN] inv-admin-frontend not found.
)
echo.

timeout /t 5 /nobreak >nul

echo ============================================
echo   Status Check
echo ============================================

netstat -ano | findstr ":8080.*LISTENING" >nul 2>&1
if errorlevel 1 (
    echo   [!!] API Server  (8080) - NOT running!
) else (
    echo   [OK] API Server  (8080) - running
)

netstat -ano | findstr ":8081.*LISTENING" >nul 2>&1
if errorlevel 1 (
    echo   [!!] Device Server (8081) - NOT running!
) else (
    echo   [OK] Device Server (8081) - running
)

netstat -ano | findstr ":3000.*LISTENING" >nul 2>&1
if errorlevel 1 (
    echo   [--] Admin API  (3000) - starting...
) else (
    echo   [OK] Admin API  (3000) - running
)

netstat -ano | findstr ":5173.*LISTENING" >nul 2>&1
if errorlevel 1 (
    echo   [--] Admin UI   (5173) - starting...
) else (
    echo   [OK] Admin UI   (5173) - running
)

echo.
echo   API Server:    http://%LOCAL_IP%:8080
echo   Device Server: http://%LOCAL_IP%:8081
echo   Admin API:     http://%LOCAL_IP%:3000
echo   Admin UI:      http://localhost:5173
echo.

goto :eof
