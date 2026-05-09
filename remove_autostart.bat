@echo off
cd /d "%~dp0"
dss.exe -remove_autostart
echo Autostart removed.
pause