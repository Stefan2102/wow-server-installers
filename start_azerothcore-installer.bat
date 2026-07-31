@echo off
where pwsh >nul 2>&1 || (echo PowerShell 7 required. & exit /b 1)
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0azerothcore-installer.ps1"