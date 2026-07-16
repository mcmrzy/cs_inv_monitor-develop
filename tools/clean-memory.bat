@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0clean-memory.ps1" %*
pause
