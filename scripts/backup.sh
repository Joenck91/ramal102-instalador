#!/bin/sh
# Um retrato completo do Ramal 102, com prova de que da para restaurar.
#
# O que entra e o que nao entra:
#
#   inbox.dump          nossas conversas, mensagens, contatos, etiquetas
#   evolution.dump      o que a Evolution guarda de cada numero
#   midia.tar.gz        os arquivos baixados (audio, imagem, documento)
#   sessoes.tar.gz      as chaves que mantem os numeros pareados
#   env.txt             senhas e chaves, sem as quais nada sobe
#
# As sessoes sao o item que mais gente esquece. Sem elas o banco volta
# inteiro mas os dois numeros aparecem desconectados, e recuperar exige
# ler o QR de novo em cada celular.
#
# O codigo NAO entra: ele vive no git, que ja e uma copia.

set -eu

DIA=$(date +%F)
DESTINO="/backups/$DIA"
INICIO=$(date +%s)

mkdir -p "$DESTINO"

# Um pedaco por vez, cada um anunciado: quando algo falhar as tres da
# manha, o log precisa dizer ONDE parou.
echo "[backup] $DIA -> $DESTINO"

# ---------------------------------------------------------------
# Bancos
# ---------------------------------------------------------------

# Formato "custom" (-Fc): ja vem comprimido e o pg_restore consegue ler
# so uma tabela dele, o que o .sql puro nao permite.
# Quantas mensagens havia ANTES e DEPOIS do dump.
#
# O pg_dump tira uma foto consistente de um instante; quantas mensagens
# ele pegou depende de qual instante foi. Comparar com uma contagem
# feita minutos depois marcava como suspeito um backup perfeito so
# porque duas mensagens chegaram no meio — e alarme falso ensina a
# ignorar o alarme.
CONTAR='SELECT count(*) FROM "Message";'
ANTES=$(PGPASSWORD="$INBOX_DB_PASSWORD" psql -h inbox-postgres -p 5432 -U inbox -q -t -A -d inbox -c "$CONTAR" 2>/dev/null || echo 0)

echo "[backup] banco do inbox..."
PGPASSWORD="$INBOX_DB_PASSWORD" pg_dump \
  -h inbox-postgres -p 5432 -U inbox -d inbox \
  -Fc -f "$DESTINO/inbox.dump"

DEPOIS=$(PGPASSWORD="$INBOX_DB_PASSWORD" psql -h inbox-postgres -p 5432 -U inbox -q -t -A -d inbox -c "$CONTAR" 2>/dev/null || echo 0)

echo "[backup] banco da Evolution..."
PGPASSWORD="$EVOLUTION_DB_PASSWORD" pg_dump \
  -h "$EVOLUTION_DB_HOST" -p "$EVOLUTION_DB_PORT" \
  -U "$EVOLUTION_DB_USER" -d "$EVOLUTION_DB_NAME" \
  -Fc -f "$DESTINO/evolution.dump"

# ---------------------------------------------------------------
# Arquivos
# ---------------------------------------------------------------

echo "[backup] midia e sessoes..."
tar -czf "$DESTINO/midia.tar.gz" -C /vol/midia .
tar -czf "$DESTINO/sessoes.tar.gz" -C /vol/sessoes .

# O .env fica com permissao restrita: e o unico arquivo do conjunto que
# sozinho da acesso a tudo.
cp /origem/.env "$DESTINO/env.txt"
chmod 600 "$DESTINO/env.txt"

# ---------------------------------------------------------------
# Prova
# ---------------------------------------------------------------
#
# Um backup que nunca foi lido de volta e um palpite. Aqui o dump do
# inbox e restaurado de verdade num banco descartavel e as linhas sao
# contadas contra o banco vivo. Custa segundos e e a diferenca entre
# "o arquivo existe" e "o arquivo serve".

echo "[backup] conferindo..."
export PGPASSWORD="$INBOX_DB_PASSWORD"
# Sem isto o "DROP DATABASE IF EXISTS" avisa que o banco nao existia, e
# esse NOTICE sai na saida de erro — no log parece que o backup falhou.
export PGOPTIONS="-c client_min_messages=warning"
PSQL="psql -h inbox-postgres -p 5432 -U inbox -q -t -A"

contar() {
  $PSQL -d "$1" -c 'SELECT count(*) FROM "Message";' 2>/dev/null || echo erro
}

$PSQL -d postgres -c 'DROP DATABASE IF EXISTS conferencia_backup;' >/dev/null
$PSQL -d postgres -c 'CREATE DATABASE conferencia_backup;' >/dev/null

CONFERIDAS=erro
if pg_restore -h inbox-postgres -p 5432 -U inbox \
     -d conferencia_backup --no-owner "$DESTINO/inbox.dump" >/dev/null 2>&1; then
  CONFERIDAS=$(contar conferencia_backup)
fi

$PSQL -d postgres -c 'DROP DATABASE IF EXISTS conferencia_backup;' >/dev/null
unset PGPASSWORD

# O dump da Evolution nao e restaurado — sao 36 MB e o que importa dele
# (as credenciais das instancias) ja esta em sessoes.tar.gz. Basta saber
# que o arquivo e legivel.
EVO_OK=nao
if pg_restore --list "$DESTINO/evolution.dump" >/dev/null 2>&1; then
  EVO_OK=sim
fi

# ---------------------------------------------------------------
# Manifesto
# ---------------------------------------------------------------

{
  echo "Ramal 102 — backup de $DIA às $(date +%H:%M)"
  echo
  echo "mensagens antes do dump : $ANTES"
  echo "mensagens depois do dump: $DEPOIS"
  echo "mensagens restauradas   : $CONFERIDAS"
  echo "dump da Evolution legivel: $EVO_OK"
  echo "segundos                : $(($(date +%s) - INICIO))"
  echo
  ls -lh "$DESTINO" | tail -n +2
} > "$DESTINO/manifesto.txt"

# A copia serve quando o que voltou esta ENTRE o que havia antes e o que
# havia depois do dump: qualquer numero dessa janela e um instante
# legitimo da foto. Fora dela, alguma coisa se perdeu.
DENTRO=nao
if [ "$CONFERIDAS" != "erro" ] &&
   [ "$CONFERIDAS" -ge "$ANTES" ] 2>/dev/null &&
   [ "$CONFERIDAS" -le "$DEPOIS" ] 2>/dev/null; then
  DENTRO=sim
fi

if [ "$DENTRO" != "sim" ] || [ "$EVO_OK" != "sim" ]; then
  echo "[backup] ATENCAO: a conferencia nao bateu. Veja $DESTINO/manifesto.txt"
  # Marca no nome da pasta: quem for procurar um backup as pressas nao
  # vai abrir o manifesto de cada um.
  mv "$DESTINO" "$DESTINO-SUSPEITO"
  exit 1
fi

echo "[backup] ok — $CONFERIDAS mensagens conferidas"

# ---------------------------------------------------------------
# Limpeza
# ---------------------------------------------------------------
#
# Guarda os catorze ultimos dias e o primeiro dia de cada mes. Assim um
# estrago percebido na mesma semana tem varios pontos de retorno, e um
# percebido meses depois ainda tem para onde voltar.

cd /backups
for pasta in $(ls -d 20*-*-* 2>/dev/null | sort -r | tail -n +15); do
  case "$pasta" in
    *-01|*-01-SUSPEITO) continue ;;
  esac
  echo "[backup] apagando $pasta"
  rm -rf "$pasta"
done

# Mensais alem de doze tambem saem: senao a pasta cresce para sempre.
for pasta in $(ls -d 20*-*-01 2>/dev/null | sort -r | tail -n +13); do
  echo "[backup] apagando mensal $pasta"
  rm -rf "$pasta"
done
