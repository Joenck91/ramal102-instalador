# Instalador do Ramal 102 — Windows.
#
# Chamado pelo instalar.bat, que so existe para permitir dois cliques.
#
# O que ele faz, em ordem: confere o Docker (e instala, se faltar),
# escreve o .env com segredos novos, sobe os containers, cria o banco e
# abre o navegador. Roda de novo sem estragar nada — cada etapa verifica
# antes de agir, porque instalador que so funciona uma vez vira um
# problema no primeiro contratempo.

$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $raiz

$URL_DOCKER = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"

function Titulo($texto) {
  Write-Host ""
  Write-Host "== $texto" -ForegroundColor Cyan
}
function Ok($texto)    { Write-Host "   $texto" -ForegroundColor Green }
function Aviso($texto) { Write-Host "   $texto" -ForegroundColor Yellow }
function Erro($texto)  { Write-Host "   $texto" -ForegroundColor Red }

function TemComando($nome) {
  $null -ne (Get-Command $nome -ErrorAction SilentlyContinue)
}

Write-Host ""
Write-Host "  Ramal 102 — instalacao" -ForegroundColor White
Write-Host "  Todos os WhatsApps numa caixa so."

# ---------------------------------------------------------------
# 1. Docker
# ---------------------------------------------------------------
#
# Duas perguntas diferentes: se esta INSTALADO e se esta RODANDO. Um
# Docker instalado e parado e o caso mais comum logo depois de instalar,
# e o erro que ele da ("cannot connect to the Docker daemon") nao diz a
# ninguem que basta abrir o programa.

Titulo "Docker"

if (-not (TemComando docker)) {
  Aviso "O Docker nao esta instalado. Vou baixar e instalar."
  Aviso "O Windows vai pedir sua autorizacao — aceite."

  $instalador = Join-Path $env:TEMP "DockerDesktopInstaller.exe"
  try {
    Write-Host "   Baixando (uns 600 MB, pode demorar)..."
    # ProgressPreference silenciado: a barra do Invoke-WebRequest deixa o
    # download varias vezes mais lento em arquivos grandes.
    $anterior = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri $URL_DOCKER -OutFile $instalador -UseBasicParsing
    $ProgressPreference = $anterior

    Write-Host "   Instalando..."
    Start-Process -FilePath $instalador `
      -ArgumentList "install", "--quiet", "--accept-license" `
      -Wait -Verb RunAs
  } catch {
    Erro "Nao consegui instalar o Docker automaticamente."
    Erro $_.Exception.Message
    Write-Host ""
    Write-Host "   Instale pela pagina oficial e rode este instalador de novo:"
    Write-Host "   https://www.docker.com/products/docker-desktop/"
    Start-Process "https://www.docker.com/products/docker-desktop/"
    exit 1
  }

  Write-Host ""
  Aviso "Docker instalado. Agora REINICIE O COMPUTADOR e rode este"
  Aviso "instalador de novo. (O Windows precisa ligar o WSL2, e isso"
  Aviso "so vale depois de reiniciar.)"
  exit 0
}

Ok "Docker instalado."

# Rodando? Ate dois minutos: o Docker Desktop demora a subir depois do
# login do Windows, e desistir em dez segundos reprovaria uma maquina boa.
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  Aviso "O Docker esta instalado mas nao esta rodando. Abrindo..."
  $exe = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
  if (Test-Path $exe) { Start-Process $exe }

  $limite = (Get-Date).AddMinutes(2)
  while ((Get-Date) -lt $limite) {
    Start-Sleep -Seconds 5
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { break }
    Write-Host "   esperando o Docker subir..."
  }

  docker info 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Erro "O Docker nao subiu."
    Write-Host ""
    Write-Host "   Abra o Docker Desktop pelo menu iniciar, espere o icone"
    Write-Host "   da baleia ficar parado, e rode este instalador de novo."
    Write-Host ""
    Write-Host "   Se ele reclamar de virtualizacao, e preciso liga-la na"
    Write-Host "   BIOS do computador — procure por 'Virtualization',"
    Write-Host "   'VT-x' ou 'SVM'. Isso nao da para fazer por aqui."
    exit 1
  }
}

Ok "Docker rodando."

# ---------------------------------------------------------------
# 2. Configuracao
# ---------------------------------------------------------------

Titulo "Configuracao"

if (Test-Path ".env") {
  Ok "Ja existe um .env — mantido como esta."
  Aviso "Se quiser comecar do zero, apague o .env e rode de novo."
} else {
  if (-not (Test-Path ".env.exemplo")) {
    Erro "Nao achei o .env.exemplo. Este instalador precisa rodar de"
    Erro "dentro da pasta do Ramal 102."
    exit 1
  }

  # Segredos aleatorios, um por instalacao. Reaproveitar os de outra
  # maquina significa que quem tem um tem todos.
  function Segredo($bytes) {
    $b = New-Object byte[] $bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    # Base64 sem os caracteres que atrapalham dentro de uma URL de banco.
    [Convert]::ToBase64String($b) -replace '[+/=]', ''
  }

  # QUEM E, antes da senha.
  #
  # A tela de entrada pede E-MAIL e senha. O instalador so perguntava a
  # senha, e o e-mail vinha do modelo - "voce@suaempresa.com.br". Quem
  # instalava chegava na tela de login sem ter o que digitar, e nao
  # havia nada em lugar nenhum que dissesse qual era.
  Write-Host ""
  Write-Host "   Quem vai usar este Ramal?"
  $nome = Read-Host "   Seu nome"
  if ([string]::IsNullOrWhiteSpace($nome)) { $nome = "Eu" }

  # Sem e-mail valido nao ha como entrar: a tela de login recusa o campo
  # vazio. Por isso a pergunta repete ate vir algo com @ no meio.
  do {
    $email = (Read-Host "   Seu e-mail (e com ele que voce entra)").Trim()
    if ($email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
      Aviso "Preciso de um e-mail valido - e por ele que voce entra."
      $email = ""
    }
  } while ([string]::IsNullOrWhiteSpace($email))

  $empresa = Read-Host "   Nome da empresa (aparece no rodape)"
  if ([string]::IsNullOrWhiteSpace($empresa)) { $empresa = "Minha empresa" }

  Write-Host ""
  Write-Host "   Escolha a senha para entrar no Ramal 102."
  Write-Host "   (deixe em branco para eu sortear uma)"
  $senhaApp = Read-Host "   Senha"
  if ([string]::IsNullOrWhiteSpace($senhaApp)) {
    $senhaApp = Segredo 9
    Aviso "Senha sorteada: $senhaApp"
    Aviso "ANOTE AGORA. Ela tambem fica no arquivo .env."
  }

  $senhaBanco     = Segredo 24
  $senhaBancoEvo  = Segredo 24
  $jwt            = Segredo 48
  $chaveEvolution = Segredo 24

  $env_ = Get-Content ".env.exemplo" -Raw
  $trocas = @{
    'ADMIN_NAME'             = $nome
    'ADMIN_EMAIL'            = $email
    'ACCOUNT_NAME'           = $empresa
    'APP_PASSWORD'           = $senhaApp
    'INBOX_DB_PASSWORD'      = $senhaBanco
    'EVOLUTION_DB_PASSWORD'  = $senhaBancoEvo
    'JWT_SECRET'             = $jwt
    'EVOLUTION_API_KEY'      = $chaveEvolution
  }
  foreach ($chave in $trocas.Keys) {
    # Troca a linha inteira, ancorada no inicio: sem a ancora,
    # "EVOLUTION_API_KEY" tambem casaria dentro de outro nome.
    $env_ = [regex]::Replace(
      $env_, "(?m)^$chave=.*$", "$chave=$($trocas[$chave])"
    )
  }
  # O DATABASE_URL carrega a senha do banco dentro dele.
  $env_ = [regex]::Replace(
    $env_, "(?m)^DATABASE_URL=.*$",
    "DATABASE_URL=postgresql://inbox:$senhaBanco@localhost:5433/inbox?schema=public"
  )

  # UTF8 sem BOM: o Docker Compose le o .env byte a byte, e um BOM vira
  # parte do nome da primeira variavel.
  [System.IO.File]::WriteAllText(
    (Join-Path $raiz ".env"), $env_,
    (New-Object System.Text.UTF8Encoding $false)
  )
  Ok "Arquivo .env criado com segredos novos."
}

# ---------------------------------------------------------------
# 3. Subir
# ---------------------------------------------------------------

Titulo "Subindo o Ramal 102"

# Dois caminhos, e o primeiro e muito melhor quando existe.
#
# BAIXAR PRONTO: o Ramal ja foi montado uma vez, no GitHub, e esta
# maquina so puxa o resultado. Menos de um minuto.
#
# MONTAR AQUI: a maquina compila tudo do zero. De cinco a quinze
# minutos, e depende de varios servidores de pacotes estarem no ar.
#
# Tenta o primeiro e cai no segundo sem perguntar nada. Nao da para
# saber de antemao: o .env pode nao apontar para imagem nenhuma, a
# internet pode estar fora, a maquina pode ser de outra arquitetura.
# Tentar e a unica forma de descobrir, e falhar aqui nao custa nada.

Write-Host "   Procurando o Ramal 102 pronto..."
docker compose pull ramal 2>&1 | Out-Null
$prontoNaMao = ($LASTEXITCODE -eq 0)
$global:LASTEXITCODE = 0

if ($prontoNaMao) {
  Ok "Baixado pronto."
  Write-Host "   Subindo."
  docker compose up -d
} elseif (Test-Path "Dockerfile") {
  Aviso "Nao havia versao pronta para baixar. Vou montar nesta maquina."
  Aviso "Isto leva de 5 a 15 minutos. Deixe a janela aberta."
  Write-Host ""
  docker compose up -d --build
} else {
  # A pasta de instalacao nao traz o codigo-fonte, so o necessario para
  # rodar. Sem o download nao ha plano B aqui — e dizer isso e melhor
  # que deixar o Docker reclamar de um Dockerfile que nunca existiu.
  Erro "Nao consegui baixar o Ramal 102, e esta pasta nao tem como monta-lo."
  Erro ""
  Erro "Quase sempre e uma destas tres:"
  Erro "  1. A internet esta fora."
  Erro "  2. O Docker Desktop nao terminou de subir. Espere e tente de novo."
  Erro "  3. Este computador nao e um PC comum (Intel/AMD)."
  Erro ""
  Erro "Para ver o que o Docker respondeu:  docker compose pull ramal"
  exit 1
}

if ($LASTEXITCODE -ne 0) {
  Erro "Alguma coisa falhou ao subir os containers."
  Erro "Rode 'docker compose logs' para ver o motivo."
  exit 1
}
Ok "Containers no ar."

# ---------------------------------------------------------------
# 4. Banco
# ---------------------------------------------------------------
#
# O schema e aplicado toda vez, nao so na primeira: o comando e
# idempotente, e assim uma atualizacao que acrescente uma coluna ja entra
# sem ninguem precisar lembrar.

Titulo "Preparando o banco"
docker compose exec -T ramal npx prisma db push 2>&1 | Select-String -NotMatch "^$"
if ($LASTEXITCODE -ne 0) {
  Erro "Nao consegui preparar o banco."
  exit 1
}
Ok "Banco pronto."

# ---------------------------------------------------------------
# 5. Esperar a aplicacao responder
# ---------------------------------------------------------------
#
# Container "no ar" nao e o mesmo que aplicacao respondendo. Abrir o
# navegador antes da hora mostra uma pagina de erro, e a primeira
# impressao seria de que a instalacao falhou.

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
  Erro "Os containers subiram, mas a aplicacao nao respondeu."
  Write-Host "   Veja o que aconteceu com: docker compose logs ramal"
  exit 1
}
Ok "Ramal 102 respondendo."

# ---------------------------------------------------------------
# Pronto
# ---------------------------------------------------------------

Write-Host ""
Write-Host "  Pronto." -ForegroundColor Green
Write-Host ""
Write-Host "  Abra:   http://localhost:3000"

# Lido do .env, e nao das variaveis das perguntas: numa reinstalacao elas
# nao sao feitas de novo, e o que vale e o que esta gravado.
$envAtual = @{}
foreach ($linha in Get-Content ".env") {
  if ($linha -match '^\s*([A-Z_]+)=(.*)$') { $envAtual[$Matches[1]] = $Matches[2] }
}
if ($envAtual['ADMIN_EMAIL']) {
  Write-Host "  Entre:  $($envAtual['ADMIN_EMAIL'])" -ForegroundColor White
  Write-Host "  Senha:  $($envAtual['APP_PASSWORD'])" -ForegroundColor White
}
Write-Host ""
Write-Host "  Falta um passo, e esse e no celular: entre, va em"
Write-Host "  'Gerenciar numeros' e leia o QR Code com o WhatsApp"
Write-Host "  que voce quer conectar."
Write-Host ""
Write-Host "  Daqui em diante o Ramal 102 sobe sozinho junto com o Windows."
Write-Host ""

Start-Process "http://localhost:3000"
