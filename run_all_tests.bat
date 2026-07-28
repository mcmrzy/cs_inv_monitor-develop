@echo off
echo ========================================
echo Flutter App 全面测试脚本
echo ========================================
echo.

cd inv_app

echo [1/4] 运行 Flutter Analyze...
flutter analyze --no-fatal-infos --no-fatal-warnings
echo Flutter Analyze 完成（warnings 不影响编译）
echo.

echo [2/4] 运行综合测试...
flutter test test\comprehensive_test.dart
if %errorlevel% neq 0 (
    echo 综合测试失败！
    pause
    exit /b 1
)
echo 综合测试通过！
echo.

echo [3/4] 运行实时数据服务测试...
flutter test test\realtime_data_service_test.dart
if %errorlevel% neq 0 (
    echo 实时数据服务测试失败！
    pause
    exit /b 1
)
echo 实时数据服务测试通过！
echo.

echo [4/4] 运行验证测试...
flutter test test\verification_test.dart
if %errorlevel% neq 0 (
    echo 验证测试失败！
    pause
    exit /b 1
)
echo 验证测试通过！
echo.

echo ========================================
echo 所有测试通过！
echo ========================================
echo.
echo 下一步：运行 App 进行功能验证
echo   flutter run
echo.
pause
