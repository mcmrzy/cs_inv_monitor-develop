@echo off
setlocal
set CURL=C:\Windows\System32\curl.exe
set BASE=http://localhost:18888/api/v1
for /f "usebackq delims=" %%i in (`%CURL% -s -X POST %BASE%/auth/login -H "Content-Type: application/json" -d "{\"account\":\"13828033200\",\"password\":\"Admin123\"}"`) do set LOGIN=%%i
echo LOGIN=%LOGIN%
%CURL% -s -X POST %BASE%/auth/login -H "Content-Type: application/json" -d "{\"account\":\"13828033200\",\"password\":\"Admin123\"}" > login.json
python -c "import json;d=json.load(open('login.json'));print(d['data']['access_token'])" > tok.txt
set /p TOK=<tok.txt
echo TOKEN_LEN=%TOK:~0,10%...
echo --- PUT with model_id=2 ---
%CURL% -s -X PUT %BASE%/devices/by-sn/CSL10TEST001 -H "Authorization: Bearer %TOK%" -H "Content-Type: application/json" -d "{\"sn\":\"CSL10TEST001\",\"model\":\"CS-I10-6k2\",\"model_id\":2}"
echo.
echo --- PUT old path ---
%CURL% -s -X PUT %BASE%/devices/by-sn/CSL10TEST001 -H "Authorization: Bearer %TOK%" -H "Content-Type: application/json" -d "{\"sn\":\"CSL10TEST001\",\"model\":\"CS-L10-6K2\"}"
echo.
endlocal
