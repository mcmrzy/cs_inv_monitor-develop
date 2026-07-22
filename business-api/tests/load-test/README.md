# Load tests

API load testing uses k6 and requires an isolated test account:

```powershell
$env:BASE_URL = 'http://127.0.0.1:18888'
$env:TEST_ACCOUNT = '<test account>'
$env:TEST_PASSWORD = '<test password>'
k6 run .\api-stress.js
```

MQTT testing must publish real QoS 1 traffic. The former JavaScript file only
incremented local counters and did not connect to a broker, so it was removed.
Use the device-server load generator instead:

```powershell
go run .\cmd\mqtt-load --broker mqtt://127.0.0.1:11883 --clients 200 --duration 60s
```

Run both tools only against an isolated staging/test environment.
