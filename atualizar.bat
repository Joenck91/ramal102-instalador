@echo off
REM Atualizador do Ramal 102 para Windows.
REM
REM Dois cliques, ou arraste a pasta da versao nova por cima deste
REM arquivo. Todo o trabalho esta no atualizar.ps1 ao lado.
REM
REM O que ele NAO toca: o .env desta maquina e a pasta backups. E o que
REM nem precisa ser protegido: conversas, numeros pareados e midia nao
REM mora na pasta, e sim em volumes do Docker.

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0atualizar.ps1" %1

REM Sem pause, a janela fecharia sozinha e ninguem leria o erro.
echo.
pause
