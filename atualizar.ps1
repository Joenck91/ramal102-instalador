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

# Roda um programa externo sem o script morrer por causa de um aviso.
#
# Isto parece firula e nao e. Com $ErrorActionPreference = "Stop", o
# "2>&1" num programa externo faz o PowerShell 5.1 embrulhar CADA
# linha que o programa escreveu no canal de erro — inclusive avisos
# inofensivos, como "a variavel X nao foi definida" — num erro de
# verdade. E um erro de verdade, com Stop ligado, mata o script.
#
# No meio de uma atualizacao isso e grave: os arquivos ja foram
# trocados e o processo para antes de subir, deixando a instalacao
# pela metade por causa de uma mensagem que nem era problema.
#
# Aqui o canal de erro e solto so durante a chamada. O codigo de saida
# do programa, que e o que realmente diz se deu certo, continua valendo
# em $LASTEXITCODE.
function Rodar {
  param([scriptblock]$Comando)
  $antes = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try { & $Comando } finally { $ErrorActionPreference = $antes }
}

# Tenta de novo antes de desistir.
#
# Baixar imagem depende de rede, e rede tropeca. Na primeira
# atualizacao de verdade, feita numa maquina de verdade, o download
# falhou uma vez e funcionou no instante seguinte, sem nada ter mudado
# — e aquela falha unica custou a atualizacao inteira.
#
# Tres tentativas com uma pausa entre elas. Nao resolve internet fora,
# e nem deveria: resolve o tropeco, que e o caso comum.
# Guarda se a recusa foi de PERMISSAO, e nao de rede. As duas falham
# igual para o Docker e sao coisas opostas para quem esta lendo a tela.
$global:semPermissao = $false

function BaixarComTeimosia {
  for ($i = 1; $i -le 3; $i++) {
    # `--progress plain` e o detalhe que faz esta funcao funcionar.
    #
    # Sem ele, o compose desenha uma barra de progresso com codigos de
    # terminal que reescrevem a linha por cima dela mesma. Capturado,
    # o texto chega picado — numa atualizacao de verdade saiu
    # "[+] pull 1/1ARNING:", com letras comidas. A palavra que esta
    # funcao procura some no meio, a recusa por falta de chave vira
    # "nao consegui baixar", e o cliente acha que comprou uma coisa
    # quebrada quando nao ha nada quebrado.
    $saida = Rodar { docker compose --progress plain pull ramal 2>&1 }
    if ($LASTEXITCODE -eq 0) { return $true }

    # "unauthorized" ou "denied" quer dizer que a imagem existe e e
    # fechada. Insistir nao resolve e so faz a pessoa esperar quinze
    # segundos por uma resposta que ja veio.
    #
    # O texto e normalizado antes: cada linha capturada pode vir como
    # objeto de erro, e juntar com espaco garante que uma palavra nao
    # fique colada na seguinte.
    $texto = ($saida | ForEach-Object { "$_" }) -join " "
    if ($texto -match "unauthorized|denied|authentication required|forbidden") {
      $global:semPermissao = $true
      return $false
    }

    if ($i -lt 3) {
      Aviso "Nao veio na tentativa $i. Esperando e tentando de novo..."
      Start-Sleep -Seconds 5
    }
  }
  return $false
}

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

# De onde vem a versao nova.
#
# O repositorio e publico de proposito: sem conta, sem senha, sem
# programa nenhum alem do que o Windows ja tem. Se um dia ele mudar de
# nome ou de dono, e esta linha que muda.
$FONTE = "https://github.com/Joenck91/ramal102-instalador/archive/refs/heads/main.zip"

# Arrastar uma pasta continua funcionando, e e a saida quando o
# download nao e possivel — maquina sem internet, rede da empresa que
# bloqueia o GitHub, ou uma versao especifica que voce quer aplicar.
$origem = $args[0]
if ($origem) { $origem = $origem.Trim().Trim([char]34) }

$baixado = $null
if (-not $origem) {
  Titulo "Buscando a versao nova"
  Write-Host "   De: github.com/Joenck91/ramal102-instalador"

  # O Windows PowerShell 5.1 ainda tenta TLS 1.0 por padrao, e o GitHub
  # recusa ha anos. Sem esta linha o download falha com um erro de
  # conexao que nao diz nada sobre a causa.
  try {
    [Net.ServicePointManager]::SecurityProtocol =
      [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  } catch { }

  $baixado = Join-Path ([System.IO.Path]::GetTempPath()) ("ramal102-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $baixado | Out-Null
  $zip = Join-Path $baixado "versao.zip"

  try {
    # A barra de progresso do Invoke-WebRequest deixa o download varias
    # vezes mais lento no PowerShell 5.1. Desligada so aqui dentro.
    $antes = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri $FONTE -OutFile $zip -UseBasicParsing
    $ProgressPreference = $antes
  } catch {
    Erro "Nao consegui baixar a versao nova."
    Erro "$($_.Exception.Message)"
    Write-Host ""
    Write-Host "   Quase sempre e internet fora, ou a rede da empresa"
    Write-Host "   bloqueando o GitHub."
    Write-Host ""
    Write-Host "   Dá para atualizar na mao: baixe o ZIP em"
    Write-Host "   github.com/Joenck91/ramal102-instalador, extraia, e"
    Write-Host "   arraste a pasta por cima deste atualizar.bat."
    Remove-Item $baixado -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
  }

  Expand-Archive -Path $zip -DestinationPath $baixado -Force
  Remove-Item $zip -Force

  # O ZIP do GitHub embrulha tudo numa pasta so, com o nome do galho.
  $origem = (Get-ChildItem $baixado -Directory | Select-Object -First 1).FullName
  if (-not $origem) {
    Erro "O arquivo baixado veio vazio."
    Remove-Item $baixado -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
  }

  # Tudo que vem da internet chega carimbado, e o carimbo passa para a
  # copia. Sem tirar aqui, o proximo duplo clique seria bloqueado pelo
  # Windows — o mesmo susto da primeira instalacao.
  Get-ChildItem $origem -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

  Ok "Versao nova baixada."
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

# O atualizar.bat fica de fora porque ELE esta rodando agora.
#
# O cmd.exe le um .bat conforme executa, guardando a posicao no
# arquivo. Trocar o arquivo embaixo dele faz a proxima leitura cair no
# meio de outra linha, e o que acontece dali em diante e imprevisivel.
# O .ps1 nao tem esse problema: o PowerShell le o arquivo inteiro antes
# de comecar.
$excluirArquivos = @(".env", ".env.antes-da-atualizacao", "atualizar.bat")

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

# E se o proprio atualizador mudou, ele fica ao lado para a pessoa
# trocar na mao. Acontece raramente — o .bat tem dezesseis linhas e
# todo o trabalho esta no .ps1, que foi atualizado normalmente.
$batNovo = Join-Path $origem "atualizar.bat"
if (Test-Path $batNovo) {
  $iguais = (Get-FileHash $batNovo).Hash -eq (Get-FileHash (Join-Path $raiz "atualizar.bat")).Hash
  if (-not $iguais) {
    Copy-Item $batNovo (Join-Path $raiz "atualizar-novo.bat") -Force
    Aviso "O proprio atualizador mudou. Depois que esta janela fechar:"
    Aviso "apague o atualizar.bat e renomeie atualizar-novo.bat no lugar."
  }
}

# O temporario ja cumpriu o papel. Apagar aqui, e nao no fim: dali para
# a frente ha varias saidas por erro, e cada uma deixaria para tras uns
# 100 KB numa pasta que ninguem olha.
if ($baixado) {
  Remove-Item $baixado -Recurse -Force -ErrorAction SilentlyContinue
  $baixado = $null
}

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

Titulo "Buscando a imagem"

# Mesma logica do instalador: baixar pronto quando existe, montar aqui
# quando nao. Ver o comentario longo no instalar.ps1.
Write-Host "   Procurando a versao pronta..."
$prontoNaMao = BaixarComTeimosia
$global:LASTEXITCODE = 0

if ($prontoNaMao) {
  Ok "Baixada."
} elseif ($global:semPermissao) {
  # A versao COMPLETA do Ramal e fechada, e quem a atualiza e o Grupo
  # Booz. Sem esta mensagem o cliente veria "unauthorized" em ingles e
  # acharia que quebrou alguma coisa — quando nada quebrou e o Ramal
  # dele nem parou.
  Write-Host ""
  Aviso "Esta e a versao completa do Ramal, e ela e atualizada por nos."
  Aviso ""
  Aviso "Nada aconteceu de errado: o seu Ramal continua no ar, do jeito"
  Aviso "que estava, com tudo no lugar."
  Aviso ""
  Aviso "Para receber a versao nova, chame o Grupo Booz no WhatsApp."
  Write-Host ""
  exit 0
} elseif (-not (Test-Path "Dockerfile")) {
  # A pasta nao traz o codigo-fonte, so o necessario para rodar. Sem o
  # download nao ha plano B — e dizer isso e melhor que deixar o Docker
  # reclamar de um Dockerfile que nunca existiu. Os arquivos ja foram
  # trocados, mas o Ramal antigo continua no ar: nada se perdeu, so nao
  # avancou.
  Erro "Nao consegui baixar a versao nova do Ramal."
  Erro ""
  Erro "O Ramal que ja estava rodando continua no ar, e os seus dados"
  Erro "estao intactos. Tente de novo quando a internet voltar."
  Erro ""
  Erro "Para ver o que o Docker respondeu:  docker compose pull ramal"
  exit 1
}

# ---------------------------------------------------------------
# 5. O banco, ANTES de trocar o Ramal
# ---------------------------------------------------------------
#
# A ordem importa e e o contrario da intuicao.
#
# Se o Ramal novo subisse primeiro e so depois o banco fosse ajustado,
# ele acordaria procurando uma coluna que ainda nao existe, morreria, e
# o Docker o reiniciaria em laco. Com ele reiniciando, nao da para
# entrar nele para ajustar o banco — e e esse o unico caminho de volta.
#
# Fazendo antes, quem roda o ajuste e um container avulso, e o Ramal
# ANTIGO segue no ar atendendo durante isso.
#
# DUAS ETAPAS, NESTA ORDEM: primeiro sai o que a versao nova
# aposentou, depois o push acerta o resto.
#
# O push so apaga coluna VAZIA. Coluna com dado dentro ele se recusa a
# apagar, e e bom que se recuse: e o unico freio entre um engano no
# schema e a coluna cheia de um cliente. Passar `--accept-data-loss`
# tiraria esse freio para sempre. Entao o que saiu de proposito esta
# escrito a mao em `src/aposentar.ts`, com data e motivo, e e so isso
# que a primeira etapa apaga.
#
# ATE A v0.9.1 A LIMPEZA RODAVA DEPOIS DO PUSH — e por isso nunca
# rodava quando precisava. Se a coluna estava vazia, o push ja a tinha
# apagado e a limpeza nao achava nada. Se tinha dado, o push se
# recusava, a atualizacao parava em "Nao consegui ajustar o banco", e
# a limpeza, que vinha depois, nao chegava a acontecer. Achado em
# 10/11/2026 ensaiando a atualizacao da Eyshila: bastava UM card
# tirado da fila com motivo anotado para ela nao conseguir atualizar.
#
# O PRECO de limpar antes: por alguns segundos, ate a troca terminar,
# o Ramal antigo pode tropecar na coluna que sumiu — a fila dele, no
# caso do motivo. E o mesmo que o push ja fazia com coluna vazia, e so
# dura o tempo da atualizacao.
Titulo "Ajustando o banco"
Rodar { docker compose up -d --wait inbox-postgres 2>&1 } | Out-Null

# A lista do que sair vem DA VERSAO NOVA, e nao deste arquivo: quem roda
# e a imagem que acabou de chegar. Por isso, quando uma versao futura
# aposentar outra coisa, este atualizador ja sabe tirar — sem precisar
# ser trocado antes.
#
# Nao derruba a atualizacao se falhar: se nada aposentado tinha dado
# dentro, o push abaixo resolve sozinho. Se tinha, e o push que vai
# parar, com a mensagem de sempre.
Rodar { docker compose run --rm --no-deps -T ramal node dist/aposentar.js 2>&1 } |
  Select-String -NotMatch "^$|Update available|prisma@latest|@prisma/client|major-version|^.{0,3}$"
if ($LASTEXITCODE -ne 0) {
  Aviso "Nao consegui tirar do banco o que a versao nova aposentou. Sigo assim mesmo."
  $global:LASTEXITCODE = 0
}

Rodar { docker compose run --rm --no-deps -T ramal npx prisma db push 2>&1 } |
  Select-String -NotMatch "^$|Update available|prisma@latest|@prisma/client|major-version|^.{0,3}$"
if ($LASTEXITCODE -ne 0) {
  Erro "Nao consegui ajustar o banco."
  Erro "O Ramal antigo continua no ar e os seus dados estao intactos."
  exit 1
}
Ok "Banco em dia."

# ---------------------------------------------------------------
# 6. Trocar o Ramal
# ---------------------------------------------------------------

Titulo "Subindo"

if ($prontoNaMao) {
  docker compose up -d
} elseif (Test-Path "Dockerfile") {
  Aviso "Sem versao pronta. Remontando aqui, o que leva alguns minutos."
  Write-Host ""
  docker compose up -d --build
}

if ($LASTEXITCODE -ne 0) {
  Erro "Falhou ao subir. Veja com: docker compose logs"
  exit 1
}
Ok "Containers no ar."

# ---------------------------------------------------------------
# 7. Esperar responder
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
