#!/bin/bash
# Volta o Ramal 102 para o estado de um backup.
#
#   scripts/restaurar.sh backups/2026-09-08            # ve o que faria
#   scripts/restaurar.sh backups/2026-09-08 --confirmo # faz
#
# Por padrao restaura so o que e nosso: o banco do inbox e a midia. As
# partes da Evolution (banco e sessoes) ficam atras de --evolution
# porque mexem em containers de OUTRO compose, que nao e nosso para
# derrubar sem aviso.
#
# Roda no host, pelo Git Bash. Precisa do Docker ligado.

set -euo pipefail

PASTA="${1:-}"
CONFIRMO=nao
EVOLUTION=nao
for arg in "${@:2}"; do
  case "$arg" in
    --confirmo) CONFIRMO=sim ;;
    --evolution) EVOLUTION=sim ;;
    *) echo "opcao desconhecida: $arg" >&2; exit 2 ;;
  esac
done

if [ -z "$PASTA" ] || [ ! -d "$PASTA" ]; then
  echo "uso: scripts/restaurar.sh <pasta-do-backup> [--confirmo] [--evolution]" >&2
  echo >&2
  echo "backups disponiveis:" >&2
  ls -d backups/*/ >&2 2>/dev/null || echo "  (nenhum)" >&2
  exit 2
fi

for arquivo in inbox.dump midia.tar.gz manifesto.txt; do
  if [ ! -f "$PASTA/$arquivo" ]; then
    echo "backup incompleto: falta $PASTA/$arquivo" >&2
    exit 1
  fi
done

echo "--- manifesto do backup ---"
cat "$PASTA/manifesto.txt"
echo "---------------------------"
echo
echo "Sera SUBSTITUIDO:"
echo "  - o banco do inbox (conversas, mensagens, contatos, etiquetas)"
echo "  - a midia baixada"
[ "$EVOLUTION" = sim ] && echo "  - o banco da Evolution e as sessoes dos numeros"
echo
echo "O que existe hoje sera perdido. Nada disso volta."
echo

if [ "$CONFIRMO" != sim ]; then
  echo "Ensaio. Para valer, repita o comando com --confirmo."
  exit 0
fi

# Uma copia do estado atual antes de destrui-lo. Restaurar o backup
# errado e um erro comum, e sem isto ele seria definitivo.
SOCORRO="backups/antes-de-restaurar-$(date +%F-%H%M)"
echo "[restaurar] guardando o estado atual em $SOCORRO"
mkdir -p "$SOCORRO"
docker compose exec -T inbox-postgres \
  pg_dump -U inbox -d inbox -Fc > "$SOCORRO/inbox.dump"

echo "[restaurar] parando o aplicativo"
docker compose stop ramal backup

echo "[restaurar] recriando o banco do inbox"
docker compose exec -T inbox-postgres \
  psql -U inbox -d postgres -q -c 'DROP DATABASE IF EXISTS inbox_restaurando;'
docker compose exec -T inbox-postgres \
  psql -U inbox -d postgres -q -c 'CREATE DATABASE inbox_restaurando;'

# Restaura para um banco novo e so entao troca os nomes: se o pg_restore
# falhar no meio, o banco original continua intacto.
docker compose exec -T inbox-postgres \
  pg_restore -U inbox -d inbox_restaurando --no-owner < "$PASTA/inbox.dump"

docker compose exec -T inbox-postgres psql -U inbox -d postgres -q <<'SQL'
SELECT pg_terminate_backend(pid) FROM pg_stat_activity
 WHERE datname IN ('inbox', 'inbox_antigo') AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS inbox_antigo;
ALTER DATABASE inbox RENAME TO inbox_antigo;
ALTER DATABASE inbox_restaurando RENAME TO inbox;
SQL
echo "[restaurar] banco trocado (o anterior ficou como inbox_antigo)"

echo "[restaurar] midia"
docker run --rm \
  -v evolutionapi_ramal_media:/destino \
  -v "$(pwd)/$PASTA":/origem:ro \
  alpine sh -c 'rm -rf /destino/* && tar -xzf /origem/midia.tar.gz -C /destino'

if [ "$EVOLUTION" = sim ]; then
  echo "[restaurar] parando a Evolution"
  docker stop evolution_api_container >/dev/null

  echo "[restaurar] sessoes dos numeros"
  docker run --rm \
    -v verificador-de-whatsapps_evolution_instances:/destino \
    -v "$(pwd)/$PASTA":/origem:ro \
    alpine sh -c 'rm -rf /destino/* && tar -xzf /origem/sessoes.tar.gz -C /destino'

  echo "[restaurar] banco da Evolution"
  docker exec -i evolution_postgres \
    psql -U evolution -d postgres -q -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='evolution' AND pid <> pg_backend_pid();"
  docker exec -i evolution_postgres \
    psql -U evolution -d postgres -q -c 'DROP DATABASE IF EXISTS evolution;'
  docker exec -i evolution_postgres \
    psql -U evolution -d postgres -q -c 'CREATE DATABASE evolution;'
  docker exec -i evolution_postgres \
    pg_restore -U evolution -d evolution --no-owner < "$PASTA/evolution.dump"

  docker start evolution_api_container >/dev/null
  echo "[restaurar] Evolution de volta"
fi

echo "[restaurar] subindo o aplicativo"
docker compose start ramal backup

echo
echo "Pronto. Confira em http://localhost:3000"
echo "O banco anterior ficou como \"inbox_antigo\" e o dump em $SOCORRO."
echo "Depois de conferir, apague com:"
echo "  docker compose exec inbox-postgres psql -U inbox -d postgres -c 'DROP DATABASE inbox_antigo;'"
