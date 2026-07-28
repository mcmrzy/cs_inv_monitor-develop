@echo off
echo ========================================
echo Flutter App 测试运行脚本
echo ========================================
echo.

cd inv_app

echo [1/3] 运行 Flutter Analyze...
flutter analyze
if %errorlevel% neq 0 (
    echo Flutter Analyze 失败！
    pause
    exit /b 1
)
echo Flutter Analyze 通过！
echo.

echo [2/3] 运行单元测试...
flutter test test\comprehensive_test.dart test\realtime_data_service_test.dart
if %errorlevel% neq 0 (
    echo 单元测试失败！
    pause
    exit /b 1
)
echo 单元测试通过！
echo.

echo [3/3] 构建 APK...
flutter build apk --debug
if %errorlevel% neq 0 (
    echo APK 构建失败！
    pause
    exit /b 1
)
echo APK 构建成功！
echo.

echo ========================================
echo 所有测试通过！
echo ========================================
pause
