@echo off
REM Desinstalador do Ramal 102 para Windows.
REM
REM Mesmo desenho do instalar.bat: este arquivo existe so para dar dois
REM cliques, e todo o trabalho esta no desinstalar.ps1 ao lado.

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0desinstalar.ps1"

REM Sem pause, a janela fecharia sozinha e ninguem leria o resumo do
REM que foi apagado — que aqui e a parte que mais importa.
echo.
pause
