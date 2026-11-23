@echo off
chcp 65001 >nul
rem Starts the app on http://127.0.0.1:8766/ and opens it in the browser.
rem The window shows a second address for the phone (same Wi-Fi).
rem To open the app without a server, double-click index.html.
cd /d "%~dp0"
start "zdorovye-server" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync\serve.ps1"
timeout /t 2 /nobreak >nul
start "" "http://127.0.0.1:8766/"
