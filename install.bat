@echo off
chcp 65001 >nul
title Claude Dev Setup
echo.
echo   Starting Claude Dev Setup...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/AdirYad/claude-dev-setup/main/install.ps1 | iex"
echo.
echo   Press any key to close this window.
pause >nul
