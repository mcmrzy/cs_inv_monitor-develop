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
rem  日志: release\logs\build_版本_时间戳.log
rem        失败时自动打印「关键错误摘要 + 日志最后 80 行」
rem  行为: 版本号第三段与构建号(+N)各自自动加一并写回 pubspec.yaml,
rem        构建失败自动还原 pubspec.yaml
rem ============================================================
echo ==============================================
echo   inv_app 发版构建 (Release APK)
echo ==============================================
echo.

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" (
    echo [错误] 未找到 PowerShell: %PS%
    goto :fail_keep_open
)

if "%PROGRAMFILES(X86)%"=="" set "PROGRAMFILES(X86)=C:\Program Files (x86)"

where flutter >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到 flutter 命令，请确认 Flutter SDK 已加入 PATH。
    echo.
    echo 常见位置: C:\Users\%USERNAME%\develop\flutter\bin
    goto :fail_keep_open
)

set "APP_VERSION="
for /f "usebackq tokens=2 delims=: " %%a in (`findstr /b /c:"version:" pubspec.yaml`) do set "APP_VERSION=%%a"
if not defined APP_VERSION (
    echo [错误] 未能从 pubspec.yaml 读取版本号。
    goto :fail_keep_open
)

set "VER_BASE="
set "VER_BUILD="
for /f "tokens=1,2 delims=+" %%a in ("%APP_VERSION%") do (
    set "VER_BASE=%%a"
    set "VER_BUILD=%%b"
)
set /a NEW_BUILD=VER_BUILD+1
for /f "tokens=1,2,3 delims=." %%i in ("%VER_BASE%") do (
    set "VER_MAJOR=%%i"
    set "VER_MINOR=%%j"
    set "VER_PATCH=%%k"
)
set /a VER_PATCH=VER_PATCH+1
set "NEW_VERSION=%VER_MAJOR%.%VER_MINOR%.%VER_PATCH%+%NEW_BUILD%"
echo 版本: %APP_VERSION% -^> %NEW_VERSION%

if not exist "release\logs" mkdir "release\logs"
set "TS="
for /f "delims=" %%t in ('%PS% -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "TS=%%t"
if not defined TS set "TS=unknown"
set "BUILD_LOG=release\logs\build_v%NEW_VERSION%_%TS%.log"
set "ANALYZE_LOG=release\logs\analyze_v%NEW_VERSION%_%TS%.log"
set "ERR_SCRIPT=%~dp0show_build_errors.ps1"
if not exist "%ERR_SCRIPT%" (
    echo [警告] 未找到错误摘要脚本: %ERR_SCRIPT%
    echo         失败时仍会保留完整日志。
)
echo 日志: %CD%\%BUILD_LOG%

copy /y pubspec.yaml "%TEMP%\pubspec.yaml.prebuild.bak" >nul
%PS% -NoProfile -Command "$f='pubspec.yaml'; $c=[IO.File]::ReadAllText($f); $c=$c -replace '(?m)^version:[^\r\n]*', 'version: %NEW_VERSION%'; [IO.File]::WriteAllText($f, $c, (New-Object Text.UTF8Encoding($false)))"
if errorlevel 1 (
    echo [警告] pubspec.yaml 更新失败, 本次仅通过 --build-number 覆盖 APK 版本号。
    copy /y "%TEMP%\pubspec.yaml.prebuild.bak" pubspec.yaml >nul
)

if /i "%~1"=="--analyze" (
    echo.
    echo [0/2] flutter analyze ...  日志: %ANALYZE_LOG%
    %PS% -NoProfile -Command "$ErrorActionPreference='Continue'; & flutter analyze 2>&1 | Tee-Object -FilePath '%ANALYZE_LOG%'; exit $LASTEXITCODE"
    if errorlevel 1 (
        echo.
        echo [错误] flutter analyze 未通过，已中止发版。
        if exist "%ERR_SCRIPT%" %PS% -NoProfile -ExecutionPolicy Bypass -File "%ERR_SCRIPT%" -LogPath "%CD%\%ANALYZE_LOG%"
        call :restore_pubspec
        goto :fail_keep_open
    )
)

echo.
echo [1/2] 开始编译: flutter build apk --release --build-number=%NEW_BUILD% ...
set "EXTRA_DEFINES="
if defined TRUSTED_DOWNLOAD_HOSTS set "EXTRA_DEFINES=--dart-define=TRUSTED_DOWNLOAD_HOSTS=%TRUSTED_DOWNLOAD_HOSTS%"

%PS% -NoProfile -Command "$ErrorActionPreference='Continue'; Write-Host 'flutter build apk --release --build-number=%NEW_BUILD% ...'; & flutter build apk --release --build-number=%NEW_BUILD% --dart-define=APP_VERSION_CODE=%NEW_BUILD% --dart-define=APP_VERSION_NAME=%VER_BASE% %EXTRA_DEFINES% 2>&1 | Tee-Object -FilePath '%BUILD_LOG%'; exit $LASTEXITCODE"

if errorlevel 1 (
    echo.
    echo [错误] 编译失败，已还原 pubspec.yaml。
    echo 完整日志: %CD%\%BUILD_LOG%
    if exist "%ERR_SCRIPT%" %PS% -NoProfile -ExecutionPolicy Bypass -File "%ERR_SCRIPT%" -LogPath "%CD%\%BUILD_LOG%"
    call :restore_pubspec
    goto :fail_keep_open
)
call :delete_pubspec_bak

set "SRC=build\app\outputs\flutter-apk\app-release.apk"
if not exist "%SRC%" (
    echo [错误] 未找到编译产物 %SRC%
    echo 完整日志: %CD%\%BUILD_LOG%
    if exist "%ERR_SCRIPT%" %PS% -NoProfile -ExecutionPolicy Bypass -File "%ERR_SCRIPT%" -LogPath "%CD%\%BUILD_LOG%"
    goto :fail_keep_open
)

if not exist "release" mkdir "release"
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
echo   日志:   %CD%\%BUILD_LOG%
echo ==============================================

endlocal
exit /b 0

:restore_pubspec
if exist "%TEMP%\pubspec.yaml.prebuild.bak" (
    copy /y "%TEMP%\pubspec.yaml.prebuild.bak" pubspec.yaml >nul
    del "%TEMP%\pubspec.yaml.prebuild.bak" >nul 2>&1
    echo [info] pubspec.yaml 已还原
)
goto :eof

:delete_pubspec_bak
del "%TEMP%\pubspec.yaml.prebuild.bak" >nul 2>&1
goto :eof

:fail_keep_open
echo.
echo 构建未完成。窗口保持打开，请查看上方输出或日志文件。
pause
exit /b 1

:hash
set "%~3="
for /f "skip=1 delims=" %%h in ('certutil -hashfile release\%~1 %~2 2^>nul') do (
    if not defined %~3 set "%~3=%%h"
)
set "%~3=!%~3: =!"
goto :eof
