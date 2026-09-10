@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
cd /d "%~dp0"

rem ============================================================
rem  inv_app 发版构建脚本
rem  用法:
rem    build_release.bat              编译 release APK 并复制到 release\
rem    build_release.bat --analyze    编译前先执行 flutter analyze
rem  产物: release\inv_app_v版本_时间戳.apk (+ .md5 / .sha256 校验文件)
rem  行为: 构建号(+N)自动加一并写回 pubspec.yaml, 构建失败自动还原
rem ============================================================
echo ==============================================
echo   inv_app 发版构建 (Release APK)
echo ==============================================
echo.

rem ---- PowerShell 绝对路径（部分环境 PATH 里没有 powershell）----
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" (
    echo [错误] 未找到 PowerShell: %PS%
    exit /b 1
)

where flutter >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到 flutter 命令，请确认 Flutter SDK 已加入 PATH。
    exit /b 1
)

rem ---- 读取 pubspec.yaml 中的版本号 ----
set "APP_VERSION="
for /f "usebackq tokens=2 delims=: " %%a in (`findstr /b /c:"version:" pubspec.yaml`) do set "APP_VERSION=%%a"
if not defined APP_VERSION (
    echo [错误] 未能从 pubspec.yaml 读取版本号。
    exit /b 1
)

rem ---- 构建号自动递增: 如 1.0.0+1 -> 1.0.0+2 ----
set "VER_BASE="
set "VER_BUILD="
for /f "tokens=1,2 delims=+" %%a in ("%APP_VERSION%") do (
    set "VER_BASE=%%a"
    set "VER_BUILD=%%b"
)
set /a NEW_BUILD=VER_BUILD+1
set "NEW_VERSION=%VER_BASE%+%NEW_BUILD%"
echo 版本: %APP_VERSION% -^> %NEW_VERSION% (构建号自动递增)

rem ---- 把新构建号写回 pubspec.yaml (备份到 TEMP, 构建失败时还原) ----
copy /y pubspec.yaml "%TEMP%\pubspec.yaml.prebuild.bak" >nul
%PS% -NoProfile -Command "$f='pubspec.yaml'; $c=[IO.File]::ReadAllText($f); $c=$c -replace '(?m)^version:[^\r\n]*', 'version: %NEW_VERSION%'; [IO.File]::WriteAllText($f, $c, (New-Object Text.UTF8Encoding($false)))"
if errorlevel 1 (
    echo [警告] pubspec.yaml 更新失败, 本次仅通过 --build-number 覆盖 APK 版本号。
    copy /y "%TEMP%\pubspec.yaml.prebuild.bak" pubspec.yaml >nul
)

rem ---- 生成时间戳（yyyyMMdd_HHmm，与系统区域设置无关）----
set "TS="
for /f "delims=" %%t in ('%PS% -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "TS=%%t"
if not defined TS set "TS=unknown"

if "%~1"=="--analyze" (
    echo.
    echo [0/2] flutter analyze ...
    call flutter analyze
    if errorlevel 1 (
        echo [错误] flutter analyze 未通过，已中止发版。
        exit /b 1
    )
)

echo.
echo [1/2] 开始编译: flutter build apk --release --build-number=%NEW_BUILD% ...
rem 可选: 追加受信下载域名(逗号分隔, 不要空格), 例如对象存储/CDN 直链域名
rem   set TRUSTED_DOWNLOAD_HOSTS=mybucket.oss-cn-beijing.aliyuncs.com
set "EXTRA_DEFINES="
if defined TRUSTED_DOWNLOAD_HOSTS set "EXTRA_DEFINES=--dart-define=TRUSTED_DOWNLOAD_HOSTS=%TRUSTED_DOWNLOAD_HOSTS%"
call flutter build apk --release --build-number=%NEW_BUILD% --dart-define=APP_VERSION_CODE=%NEW_BUILD% --dart-define=APP_VERSION_NAME=%VER_BASE% %EXTRA_DEFINES%
if errorlevel 1 (
    echo [错误] 编译失败, 已还原 pubspec.yaml, 请检查上方日志。
    copy /y "%TEMP%\pubspec.yaml.prebuild.bak" pubspec.yaml >nul
    del "%TEMP%\pubspec.yaml.prebuild.bak" >nul 2>&1
    exit /b 1
)
del "%TEMP%\pubspec.yaml.prebuild.bak" >nul 2>&1

set "SRC=build\app\outputs\flutter-apk\app-release.apk"
if not exist "%SRC%" (
    echo [错误] 未找到编译产物 %SRC%
    exit /b 1
)

if not exist "release" mkdir "release"
rem 文件名中的 "+"(build号) 规范为 _build，避免 URL/下载场景转义问题
set "VER_NAME=%NEW_VERSION%"
for /f "tokens=1,2 delims=+" %%a in ("%NEW_VERSION%") do (
    if not "%%b"=="" set "VER_NAME=%%a_build%%b"
)
set "DEST_NAME=inv_app_v%VER_NAME%_%TS%.apk"
copy /y "%SRC%" "release\%DEST_NAME%" >nul

echo.
echo [2/2] 生成 MD5 / SHA-256 校验文件 ...
call :hash "%DEST_NAME%" MD5 MD5SUM
call :hash "%DEST_NAME%" SHA256 SHASUM
echo %MD5SUM%  %DEST_NAME%>"release\%DEST_NAME%.md5"
echo %SHASUM%  %DEST_NAME%>"release\%DEST_NAME%.sha256"

for %%F in ("release\%DEST_NAME%") do set "SIZE=%%~zF"
set /a SIZE_MB=%SIZE% / 1048576

echo.
echo ==============================================
echo   构建完成!
echo   版本号: %NEW_VERSION% (pubspec.yaml 已更新, 请随代码提交)
echo   APK:    %CD%\release\%DEST_NAME%
echo   大小:   %SIZE_MB% MB
echo   MD5:    %MD5SUM%
echo   SHA256: %SHASUM%
echo ==============================================

endlocal
exit /b 0

rem ---- certutil hash helper: args = filename, algorithm (MD5 or SHA256), result var name ----
:hash
set "%~3="
for /f "skip=1 delims=" %%h in ('certutil -hashfile release\%~1 %~2 2^>nul') do (
    if not defined %~3 set "%~3=%%h"
)
set "%~3=!%~3: =!"
goto :eof
