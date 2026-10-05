@echo off
REM Instalador do Ramal 102 para Windows.
REM
REM Este arquivo existe so para dar dois cliques. Todo o trabalho esta no
REM instalar.ps1 ao lado: o .bat nao sabe baixar arquivo, gerar senha nem
REM ler JSON, e o PowerShell ja vem em qualquer Windows desde o 7.
REM
REM -ExecutionPolicy Bypass vale so para esta execucao: nao mexe na
REM configuracao da maquina.

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar.ps1"

REM Sem pause, a janela fecharia sozinha e ninguem leria o erro.
echo.
pause
