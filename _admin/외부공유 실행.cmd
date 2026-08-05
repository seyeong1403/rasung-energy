@echo off
chcp 65001 > nul
title Lasung Energy - Admin Share
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0share.ps1"
pause
