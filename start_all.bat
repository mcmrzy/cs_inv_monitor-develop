@echo off
echo Starting all backend services...
echo.

echo [1/4] Stopping old services...
taskkill /F /IM mosquitto.exe >nul 2>&1
taskkill /F /IM inv_device_server.exe >nul 2>&1
taskkill /F /IM inv-device-server.exe >nul 2>&1
taskkill /F /IM inv_api_server.exe >nul 2>&1
taskkill /F /IM inv-api-server.exe >nul 2>&1
net stop mosquitto >nul 2>&1
timeout /t 2 /nobreak >nul

echo [2/4] Starting Mosquitto MQTT Broker (1883 + 8083)...
start "MQTT-Broker" /min "C:\Program Files\mosquitto\mosquitto.exe" -c "d:\INV-MQTT\mosquitto_custom.conf" -v
timeout /t 3 /nobreak >nul

echo [3/4] Starting inv_device_server (8081)...
start "Device-Server" /min /d "d:\INV-MQTT\inv_device_server" cmd /c "inv_device_server.exe"

echo [4/4] Starting inv_api_server (8080)...
start "API-Server" /min /d "d:\INV-MQTT\inv_api_server" cmd /c "inv_api_server.exe"

timeout /t 3 /nobreak >nul

echo.
echo All services started!
echo.
echo API Server:  http://192.168.8.115:8080
echo Admin Panel: http://192.168.8.115:8080/admin
echo MQTT TCP:    192.168.8.115:1883
echo MQTT WS:     192.168.8.115:8083
echo Device Srv:  192.168.8.115:8081
echo.
echo To simulate a device:
echo   cd C:\Program Files\mosquitto
echo   mosquitto_pub -h localhost -p 1883 -t cs_inv/H1CNC0013500001F/status -m "{\"device_sn\":\"H1CNC0013500001F\",\"online\":true}"
echo.
pause