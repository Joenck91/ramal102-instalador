#!/usr/bin/env bash
# Instalador do Ramal 102 — Linux e macOS.
#
#   chmod +x instalar.sh && ./instalar.sh
#
# Faz o mesmo que o instalar.bat do Windows, com uma diferenca no meio:
# no Linux o Docker se instala sozinho pelo script oficial; no macOS,
# nao. La o Docker Desktop vem num .dmg que precisa ser arrastado a mao,
# e automatizar isso exigiria o Homebrew — que e mais um pre-requisito
# para quem talvez nao tenha nenhum. Entao no Mac o script abre a pagina
# e pede para rodar de novo depois.

set -euo pipefail
cd "$(dirname "$0")"
RAIZ="$PWD"

azul=$'\033[36m'; verde=$'\033[32m'; amarelo=$'\033[33m'
vermelho=$'\033[31m'; fim=$'\033[0m'

titulo() { printf '\n%s== %s%s\n' "$azul" "$1" "$fim"; }
ok()     { printf '   %s%s%s\n' "$verde" "$1" "$fim"; }
aviso()  { printf '   %s%s%s\n' "$amarelo" "$1" "$fim"; }
erro()   { printf '   %s%s%s\n' "$vermelho" "$1" "$fim"; }

echo
echo "  Ramal 102 — instalacao"
echo "  Todos os WhatsApps numa caixa so."

SISTEMA=$(uname -s)

# ---------------------------------------------------------------
# 1. Docker
# ---------------------------------------------------------------

titulo "Docker"

if ! command -v docker >/dev/null 2>&1; then
  if [ "$SISTEMA" = "Darwin" ]; then
    erro "O Docker nao esta instalado."
    echo
    echo "   No Mac ele precisa ser instalado a mao:"
    echo "   1. baixe em https://www.docker.com/products/docker-desktop/"
    echo "   2. abra o .dmg e arraste o Docker para Aplicativos"
    echo "   3. abra o Docker uma vez e aceite os termos"
    echo "   4. rode este instalador de novo"
    command -v open >/dev/null 2>&1 &&
      open "https://www.docker.com/products/docker-desktop/"
    exit 1
  fi

  aviso "O Docker nao esta instalado. Vou instalar pelo script oficial."
  aviso "Sua senha de administrador sera pedida."
  # get.docker.com e mantido pela propria Docker e cobre as distribuicoes
  # comuns. Baixar-e-executar nao e habito bom, mas aqui a origem e a
  # mesma de onde viria o pacote de qualquer jeito.
  curl -fsSL https://get.docker.com -o /tmp/instalar-docker.sh
  sudo sh /tmp/instalar-docker.sh
  rm -f /tmp/instalar-docker.sh

  # Sem isto, todo comando docker exige sudo — e o compose rodaria como
  # root, deixando arquivos que o dono da pasta nao consegue apagar.
  if ! groups | grep -qw docker; then
    sudo usermod -aG docker "$USER"
    echo
    aviso "Seu usuario foi adicionado ao grupo 'docker'."
    aviso "SAIA E ENTRE DE NOVO na sessao (ou reinicie) e rode este"
    aviso "instalador outra vez."
    exit 0
  fi
fi

ok "Docker instalado."

if ! docker info >/dev/null 2>&1; then
  if [ "$SISTEMA" = "Darwin" ]; then
    aviso "O Docker esta instalado mas nao esta rodando. Abrindo..."
    open -a Docker || true
    limite=$(( $(date +%s) + 120 ))
    while [ "$(date +%s)" -lt "$limite" ]; do
      sleep 5
      docker info >/dev/null 2>&1 && break
      echo "   esperando o Docker subir..."
    done
  else
    aviso "O servico do Docker esta parado. Ligando..."
    sudo systemctl start docker || true
    sleep 5
  fi

  if ! docker info >/dev/null 2>&1; then
    erro "O Docker nao subiu."
    echo "   Abra o Docker Desktop (ou 'sudo systemctl start docker') e"
    echo "   rode este instalador de novo."
    exit 1
  fi
fi

ok "Docker rodando."

# `docker compose` (plugin) e o que este projeto usa. O `docker-compose`
# antigo, com hifen, nao entende algumas coisas do nosso arquivo.
if ! docker compose version >/dev/null 2>&1; then
  erro "Falta o plugin 'docker compose'."
  echo "   Instale o pacote docker-compose-plugin da sua distribuicao."
  exit 1
fi

# ---------------------------------------------------------------
# 2. Configuracao
# ---------------------------------------------------------------

titulo "Configuracao"

if [ -f .env ]; then
  ok "Ja existe um .env — mantido como esta."
  aviso "Se quiser comecar do zero, apague o .env e rode de novo."
else
  [ -f .env.exemplo ] || {
    erro "Nao achei o .env.exemplo. Este instalador precisa rodar de"
    erro "dentro da pasta do Ramal 102."
    exit 1
  }

  # Segredos aleatorios, um por instalacao. Os caracteres +/= saem porque
  # atrapalham dentro de uma URL de banco.
  segredo() { LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$1"; }

  # QUEM E, antes da senha. A tela de entrada pede E-MAIL e senha, e o
  # e-mail vinha do modelo — quem instalava chegava no login sem ter o
  # que digitar.
  echo
  echo "   Quem vai usar este Ramal?"
  printf "   Seu nome: "
  read -r NOME
  [ -n "$NOME" ] || NOME="Eu"

  EMAIL=""
  while [ -z "$EMAIL" ]; do
    printf "   Seu e-mail (e com ele que voce entra): "
    read -r EMAIL
    case "$EMAIL" in
      *@*.*) ;;
      *) aviso "Preciso de um e-mail valido — e por ele que voce entra."
         EMAIL="" ;;
    esac
  done

  printf "   Nome da empresa (aparece no rodape): "
  read -r EMPRESA
  [ -n "$EMPRESA" ] || EMPRESA="Minha empresa"

  echo
  echo "   Escolha a senha para entrar no Ramal 102."
  echo "   (deixe em branco para eu sortear uma)"
  printf "   Senha: "
  read -r SENHA_APP
  if [ -z "$SENHA_APP" ]; then
    SENHA_APP=$(segredo 12)
    aviso "Senha sorteada: $SENHA_APP"
    aviso "ANOTE AGORA. Ela tambem fica no arquivo .env."
  fi

  SENHA_BANCO=$(segredo 32)
  SENHA_BANCO_EVO=$(segredo 32)
  JWT=$(segredo 64)
  CHAVE_EVO=$(segredo 32)

  # `|` como separador no sed: as senhas podem conter barras.
  sed \
    -e "s|^ADMIN_NAME=.*|ADMIN_NAME=${NOME}|" \
    -e "s|^ADMIN_EMAIL=.*|ADMIN_EMAIL=${EMAIL}|" \
    -e "s|^ACCOUNT_NAME=.*|ACCOUNT_NAME=${EMPRESA}|" \
    -e "s|^APP_PASSWORD=.*|APP_PASSWORD=${SENHA_APP}|" \
    -e "s|^INBOX_DB_PASSWORD=.*|INBOX_DB_PASSWORD=${SENHA_BANCO}|" \
    -e "s|^EVOLUTION_DB_PASSWORD=.*|EVOLUTION_DB_PASSWORD=${SENHA_BANCO_EVO}|" \
    -e "s|^JWT_SECRET=.*|JWT_SECRET=${JWT}|" \
    -e "s|^EVOLUTION_API_KEY=.*|EVOLUTION_API_KEY=${CHAVE_EVO}|" \
    -e "s|^DATABASE_URL=.*|DATABASE_URL=postgresql://inbox:${SENHA_BANCO}@localhost:5433/inbox?schema=public|" \
    .env.exemplo > .env

  chmod 600 .env
  ok "Arquivo .env criado com segredos novos."
fi

# ---------------------------------------------------------------
# 3. Subir
# ---------------------------------------------------------------

titulo "Subindo o Ramal 102"

# Dois caminhos. Baixar pronto (o Ramal ja foi montado uma vez no
# GitHub) leva menos de um minuto; montar aqui leva de 5 a 15 e depende
# de varios servidores de pacotes estarem no ar. Tenta o primeiro e cai
# no segundo sozinho — nao da para saber de antemao qual vai dar certo,
# e falhar na tentativa nao custa nada.

echo "   Procurando o Ramal 102 pronto..."
if docker compose pull ramal >/dev/null 2>&1; then
  ok "Baixado pronto."
  echo "   Subindo."
  docker compose up -d
elif [ -f Dockerfile ]; then
  aviso "Nao havia versao pronta para baixar. Vou montar nesta maquina."
  aviso "Isto leva de 5 a 15 minutos."
  echo
  docker compose up -d --build
else
  # A pasta de instalacao nao traz o codigo-fonte, so o necessario para
  # rodar. Sem o download nao ha plano B aqui.
  erro "Nao consegui baixar o Ramal 102, e esta pasta nao tem como monta-lo."
  erro "Veja o que o Docker respondeu com:  docker compose pull ramal"
  exit 1
fi
ok "Containers no ar."

# ---------------------------------------------------------------
# 4. Banco
# ---------------------------------------------------------------
#
# Aplicado toda vez, nao so na primeira: o comando e idempotente, e assim
# uma atualizacao que acrescente uma coluna entra sem ninguem lembrar.

titulo "Preparando o banco"
docker compose exec -T ramal npx prisma db push
ok "Banco pronto."

# ---------------------------------------------------------------
# 5. Esperar a aplicacao responder
# ---------------------------------------------------------------

titulo "Conferindo"
limite=$(( $(date +%s) + 120 ))
respondeu=nao
while [ "$(date +%s)" -lt "$limite" ]; do
  if curl -fsS http://localhost:3000/health >/dev/null 2>&1; then
    respondeu=sim
    break
  fi
  sleep 3
done

if [ "$respondeu" != sim ]; then
  erro "Os containers subiram, mas a aplicacao nao respondeu."
  echo "   Veja o que aconteceu com: docker compose logs ramal"
  exit 1
fi
ok "Ramal 102 respondendo."

echo
printf '  %sPronto.%s\n' "$verde" "$fim"
echo
echo "  Abra:   http://localhost:3000"
# Lido do .env: numa reinstalacao as perguntas nao sao refeitas, e o
# que vale e o que esta gravado.
EMAIL_ATUAL=$(grep -E "^ADMIN_EMAIL=" .env | cut -d= -f2-)
SENHA_ATUAL=$(grep -E "^APP_PASSWORD=" .env | cut -d= -f2-)
[ -n "$EMAIL_ATUAL" ] && echo "  Entre:  $EMAIL_ATUAL"
[ -n "$SENHA_ATUAL" ] && echo "  Senha:  $SENHA_ATUAL"
echo
echo "  Falta um passo, e esse e no celular: entre, va em"
echo "  'Gerenciar numeros' e leia o QR Code com o WhatsApp"
echo "  que voce quer conectar."
echo

if [ "$SISTEMA" = "Darwin" ]; then
  open http://localhost:3000 2>/dev/null || true
else
  xdg-open http://localhost:3000 2>/dev/null || true
fi
