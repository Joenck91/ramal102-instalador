#Requires -Version 5.1
<#
  Tira o Ramal 102 desta maquina.

  Existe porque apagar a pasta NAO desinstala, e ninguem adivinha isso.
  As conversas, os numeros pareados e as configuracoes moram em volumes
  do Docker — invisiveis no Explorador de Arquivos, varios gigabytes, e
  que ficam ocupando disco para sempre depois que a pasta some.

  Tres saidas, e a pergunta e uma so. Encadear "quer apagar? e isso
  tambem? e aquilo?" cansa, e cansado se responde sim no automatico —
  que e exatamente o que nao pode acontecer aqui.

  O que este script NAO faz, de proposito:

    nao apaga a pasta onde ele esta  ele roda de dentro dela; apagar o
                                     chao enquanto se esta em pe e como
                                     um erro no meio termina
    nao apaga copia sem perguntar    a copia de seguranca tem as
                                     conversas, e e o unico caminho de
                                     volta depois da opcao 2
#>

$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $raiz

function Titulo($t) { Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }
function Ok($t)     { Write-Host "   $t" -ForegroundColor Green }
function Aviso($t)  { Write-Host "   $t" -ForegroundColor Yellow }
function Erro($t)   { Write-Host "   $t" -ForegroundColor Red }
function Diz($t)    { Write-Host "   $t" }

# O mesmo embrulho do instalador: com ErrorActionPreference em "Stop",
# um aviso qualquer do Docker na saida de erro derrubaria o script no
# meio — e no meio, aqui, e o pior lugar possivel para parar.
function Rodar([scriptblock]$bloco) {
  $antes = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try { & $bloco } finally { $ErrorActionPreference = $antes }
}

Write-Host ""
Write-Host "  Ramal 102 - desinstalacao" -ForegroundColor White
Write-Host ""

if (-not (Test-Path "docker-compose.yaml")) {
  Erro "Este script precisa rodar de dentro da pasta onde o Ramal foi"
  Erro "instalado - a mesma onde estao o instalar.bat e o .env."
  exit 1
}

# ---------------------------------------------------------------
# O que existe hoje
# ---------------------------------------------------------------
Titulo "O que esta instalado"

$noAr = Rodar { docker compose ps --services --filter "status=running" 2>$null }
if ($noAr) {
  Diz "No ar agora: $($noAr -join ', ')"
} else {
  Diz "Nenhum container no ar."
}

# O tamanho e o argumento mais convincente de todos: um numero na tela
# faz entender que ha algo a limpar, mesmo sem se ver nada na pasta.
$nomes = @(
  "inbox_postgres", "ramal_media", "backup_sinal",
  "evolution_postgres", "evolution_instances", "evolution_store"
)
$todos = Rodar { docker volume ls --format "{{.Name}}" 2>$null }
$meus = @($todos | Where-Object { $atual = $_; ($nomes | Where-Object { $atual -like "*$_" }).Count -gt 0 })
if ($meus.Count -gt 0) {
  Diz "Dados guardados em $($meus.Count) volume(s) do Docker."
} else {
  Aviso "Nao achei volumes deste Ramal. Talvez ele ja tenha sido removido."
}

$pastaBackup = Join-Path $raiz "backups"
$copias = 0
if (Test-Path $pastaBackup) {
  $copias = @(Get-ChildItem $pastaBackup -Directory -ErrorAction SilentlyContinue).Count
}
if ($copias -gt 0) {
  Diz "Copias de seguranca: $copias, em $pastaBackup"
}

# ---------------------------------------------------------------
# Guardar uma copia antes
# ---------------------------------------------------------------
if ($meus.Count -gt 0) {
  Titulo "Antes de mais nada"
  Write-Host ""
  Write-Host "   Quer guardar uma copia das suas conversas agora?" -ForegroundColor White
  Write-Host "   Ela fica na pasta backups, fora do Docker."
  Write-Host ""
  $quer = Read-Host "   Guardar copia? (s/N)"
  if ($quer -match '^[sS]') {
    Titulo "Guardando a copia"
    Diz "Pode levar alguns minutos. Nao feche esta janela."
    Rodar { docker compose up -d --wait inbox-postgres evolution-postgres 2>&1 } | Out-Null
    Rodar { docker compose run --rm -T backup sh /scripts/backup.sh 2>&1 } |
      ForEach-Object { Write-Host "   $_" }
    if ($LASTEXITCODE -eq 0) {
      Ok "Copia guardada em $pastaBackup"
      $copias = $copias + 1
    } else {
      Erro "A copia NAO foi feita."
      Write-Host ""
      $seguir = Read-Host "   Continuar a desinstalacao assim mesmo? (s/N)"
      if ($seguir -notmatch '^[sS]') { Diz "Nada foi mexido."; exit 1 }
    }
  }
}

# ---------------------------------------------------------------
# A pergunta, uma so
# ---------------------------------------------------------------
Titulo "O que fazer com os dados"
Write-Host ""
Write-Host "   1  Tirar o Ramal e GUARDAR os dados" -ForegroundColor White
Write-Host "      As conversas ficam no computador. Reinstalando depois,"
Write-Host "      tudo volta como estava."
Write-Host ""
Write-Host "   2  APAGAR os dados e manter as copias de seguranca" -ForegroundColor White
Write-Host "      Conversas, numeros pareados e configuracoes somem. As"
Write-Host "      copias na pasta backups ficam."
Write-Host ""
Write-Host "   3  APAGAR TUDO, inclusive as copias" -ForegroundColor White
Write-Host "      Nao sobra nada deste Ramal nesta maquina."
Write-Host ""
Write-Host "   0  Desistir e nao mexer em nada" -ForegroundColor White
Write-Host ""

$escolha = Read-Host "   Escolha (0/1/2/3)"
if (@("1", "2", "3") -notcontains $escolha) {
  Write-Host ""
  Diz "Nada foi mexido. O Ramal continua como estava."
  exit 0
}

$apagaDados = (@("2", "3") -contains $escolha)
$apagaCopias = ($escolha -eq "3")

# ---------------------------------------------------------------
# A confirmacao que nao da para dar sem ler
# ---------------------------------------------------------------
if ($apagaDados) {
  Write-Host ""
  Erro "ISTO NAO TEM VOLTA."
  Write-Host ""
  if ($apagaCopias) {
    Diz "Vao ser apagados: todas as conversas, os numeros pareados, as"
    Diz "configuracoes E as copias de seguranca. Nada sobra."
  } else {
    Diz "Vao ser apagadas todas as conversas, os numeros pareados e as"
    Diz "configuracoes. As copias em backups ficam."
    if ($copias -eq 0) {
      Write-Host ""
      Aviso "E nao ha nenhuma copia guardada. Depois disto nao ha"
      Aviso "caminho de volta."
    }
  }
  Write-Host ""
  # Digitar a palavra, e nao "s". Um "s" distraido e um enter — esta e
  # a unica barreira entre um clique errado e anos de conversa.
  $palavra = Read-Host "   Digite APAGAR para confirmar"
  if ($palavra -cne "APAGAR") {
    Write-Host ""
    Diz "Nao era isso. Nada foi mexido."
    exit 0
  }
}

# ---------------------------------------------------------------
# Fazer
# ---------------------------------------------------------------
Titulo "Parando o Ramal"
if ($apagaDados) {
  Rodar { docker compose down -v 2>&1 } | ForEach-Object { Write-Host "   $_" }
} else {
  Rodar { docker compose down 2>&1 } | ForEach-Object { Write-Host "   $_" }
}
if ($LASTEXITCODE -ne 0) {
  Erro "O Docker recusou. Ele esta aberto? O icone da baleia fica perto"
  Erro "do relogio. Abra o Docker Desktop e rode de novo."
  exit 1
}
if ($apagaDados) {
  Ok "Parado, e os dados foram apagados."
} else {
  Ok "Parado. Os dados continuam guardados."
}

if ($apagaCopias -and (Test-Path $pastaBackup)) {
  Titulo "Apagando as copias"
  Remove-Item $pastaBackup -Recurse -Force
  Ok "Pasta backups apagada."
}

# As imagens sao o programa, e nao os dados — por isso ficam numa
# pergunta separada. Sao varios gigabytes, e quem esta desinstalando
# costuma querer o espaco de volta.
if ($apagaDados) {
  Write-Host ""
  $limpar = Read-Host "   Apagar tambem os programas baixados e liberar o espaco? (s/N)"
  if ($limpar -match '^[sS]') {
    Titulo "Liberando espaco"
    Rodar { docker compose down --rmi all 2>&1 } | ForEach-Object { Write-Host "   $_" }
    Ok "Imagens removidas."
  }
}

# ---------------------------------------------------------------
# O que sobrou, dito em voz alta
# ---------------------------------------------------------------
Titulo "Pronto"
Write-Host ""
if (-not $apagaDados) {
  Diz "O Ramal foi parado e removido, e os seus dados continuam aqui."
  Diz "Para ter tudo de volta, rode o instalar.bat nesta mesma pasta."
} elseif ((-not $apagaCopias) -and ($copias -gt 0)) {
  Diz "O Ramal saiu daqui. As suas copias de seguranca continuam em:"
  Diz "   $pastaBackup"
  Diz "Apague a pasta na mao se quiser que elas sumam tambem."
} else {
  Diz "Nao sobrou nada deste Ramal na maquina."
}
Write-Host ""
# Dito por ultimo porque e o unico passo que fica com a pessoa: o
# script nao pode apagar a pasta de onde ele mesmo esta rodando.
Diz "Falta so apagar esta pasta, na mao:"
Diz "   $raiz"
Write-Host ""
