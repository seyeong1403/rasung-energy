@echo off
chcp 65001 > nul
title Lasung Energy - Upload
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0호스팅 올리기.ps1"
pause
