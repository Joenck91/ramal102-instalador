# Atualizador do Ramal 102 — Windows.
#
# Roda na maquina de quem JA usa, para trazer uma versao nova sem perder
# nada do que ela fez ate aqui.
#
# O que ele protege, e por que sao exatamente estes dois:
#
#   .env      — os segredos daquela maquina. Sobrescrever com os de
#               outra faz o banco parar de abrir: a senha gravada dentro
#               do Postgres continua sendo a antiga.
#   backups/  — as copias de seguranca dela. Nao sao suas.
#
# E o que NAO precisa de protecao nenhuma, que e quase tudo: conversas,
# etiquetas, notas, favoritas, retornos, midia baixada e as chaves que
# mantem cada numero pareado vivem em VOLUMES do Docker, fora da pasta.
# Trocar os arquivos daqui nao encosta neles — e por isso atualizar nao
# pede para ler QR Code de novo.

$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $raiz

function Titulo($t) { Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }
function Ok($t)     { Write-Host "   $t" -ForegroundColor Green }
function Aviso($t)  { Write-Host "   $t" -ForegroundColor Yellow }
function Erro($t)   { Write-Host "   $t" -ForegroundColor Red }

Write-Host ""
Write-Host "  Ramal 102 — atualizacao" -ForegroundColor White

# ---------------------------------------------------------------
# 1. Onde esta a versao nova
# ---------------------------------------------------------------

$origem = $args[0]
if (-not $origem) {
  Write-Host ""
  Write-Host "   Arraste para aqui a pasta com a versao nova e tecle Enter."
  $origem = (Read-Host "   Pasta").Trim()
  # Arrastar uma pasta no Windows entrega o caminho entre aspas.
  $origem = $origem.Trim([char]34)
}

if (-not (Test-Path (Join-Path $origem "docker-compose.yaml"))) {
  Erro "Isso nao parece a pasta do Ramal 102."
  Erro "Procurei um docker-compose.yaml em: $origem"
  exit 1
}
if ((Resolve-Path $origem).Path -eq (Resolve-Path $raiz).Path) {
  Erro "A pasta de origem e esta mesma. Aponte para a versao nova."
  exit 1
}

# ---------------------------------------------------------------
# 2. Uma copia do .env antes de qualquer coisa
# ---------------------------------------------------------------
#
# Cinto e suspensorio: a copia abaixo ja pula o .env, mas se algum dia
# ela deixar de pular, esta copia e a diferenca entre um susto e um
# banco inacessivel.

Titulo "Guardando os seus segredos"
if (Test-Path ".env") {
  $guardado = ".env.antes-da-atualizacao"
  Copy-Item ".env" $guardado -Force
  Ok "Copia do .env em $guardado"
} else {
  Aviso "Nao ha .env aqui — entao isto e uma instalacao nova."
  Aviso "Rode o instalar.bat em vez deste."
  exit 1
}

# ---------------------------------------------------------------
# 3. Trocar os arquivos
# ---------------------------------------------------------------
#
# O robocopy e quem sabe espelhar uma pasta sem tocar no que foi
# excluido. /XD e /XF sao as exclusoes — e a lista e curta de proposito:
# tudo que nao esta nela pode ser trocado sem consequencia.

Titulo "Trazendo a versao nova"
Write-Host "   (o .env e a pasta backups ficam como estao)"

$excluirPastas = @("backups", "node_modules", ".git", "media")
$excluirArquivos = @(".env", ".env.antes-da-atualizacao")

$argumentos = @($origem, $raiz, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NP")
$argumentos += "/XD"; $argumentos += $excluirPastas
$argumentos += "/XF"; $argumentos += $excluirArquivos

& robocopy @argumentos | Out-Null
# O robocopy usa 0-7 para sucesso; 8 ou mais e falha de verdade.
if ($LASTEXITCODE -ge 8) {
  Erro "Nao consegui copiar os arquivos (codigo $LASTEXITCODE)."
  exit 1
}
$global:LASTEXITCODE = 0
Ok "Arquivos atualizados."

# ---------------------------------------------------------------
# 4. Conferir que o .env sobreviveu
# ---------------------------------------------------------------
#
# Uma comparacao boba que ja evitaria o pior dos acidentes.

$agora = Get-FileHash ".env" -Algorithm SHA256
$antes = Get-FileHash ".env.antes-da-atualizacao" -Algorithm SHA256
if ($agora.Hash -ne $antes.Hash) {
  Aviso "O .env mudou. Devolvendo o seu."
  Copy-Item ".env.antes-da-atualizacao" ".env" -Force
}
Ok "Segredos preservados."

# ---------------------------------------------------------------
# 5. Subir a versao nova
# ---------------------------------------------------------------

Titulo "Subindo"

# Mesma logica do instalador: baixar pronto quando existe, montar aqui
# quando nao. Ver o comentario longo no instalar.ps1.
Write-Host "   Procurando a versao pronta..."
docker compose pull ramal 2>&1 | Out-Null
$prontoNaMao = ($LASTEXITCODE -eq 0)
$global:LASTEXITCODE = 0

if ($prontoNaMao) {
  Ok "Baixada."
  docker compose up -d
} else {
  Aviso "Sem versao pronta. Remontando aqui, o que leva alguns minutos."
  Write-Host ""
  docker compose up -d --build
}

if ($LASTEXITCODE -ne 0) {
  Erro "Falhou ao subir. Veja com: docker compose logs"
  exit 1
}
Ok "Containers no ar."

# Mudancas de banco entram aqui. O comando e idempotente: quando nao ha
# nada novo, ele nao faz nada.
Titulo "Ajustando o banco"
docker compose exec -T ramal npx prisma db push 2>&1 | Select-String -NotMatch "^$"
if ($LASTEXITCODE -ne 0) {
  Erro "Nao consegui ajustar o banco."
  exit 1
}
Ok "Banco em dia."

# ---------------------------------------------------------------
# 6. Esperar responder
# ---------------------------------------------------------------

Titulo "Conferindo"
$limite = (Get-Date).AddMinutes(2)
$respondeu = $false
while ((Get-Date) -lt $limite) {
  try {
    $r = Invoke-WebRequest -Uri "http://localhost:3000/health" `
           -UseBasicParsing -TimeoutSec 5
    if ($r.StatusCode -eq 200) { $respondeu = $true; break }
  } catch { }
  Start-Sleep -Seconds 3
}

if (-not $respondeu) {
  Erro "Subiu, mas a aplicacao nao respondeu."
  Write-Host "   Veja com: docker compose logs ramal"
  exit 1
}

Write-Host ""
Write-Host "  Atualizado." -ForegroundColor Green
Write-Host ""
Write-Host "  Suas conversas, numeros e configuracoes continuam como estavam."
Write-Host "  Abra: http://localhost:3000"
Write-Host ""

Start-Process "http://localhost:3000"
