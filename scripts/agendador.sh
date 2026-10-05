#!/bin/sh
# Decide QUANDO o backup roda. Duas razoes o disparam:
#
#   o relogio  — uma vez por dia, na hora configurada
#   um pedido  — alguem clicou "Atualizar agora" no aplicativo
#
# O pedido chega como um arquivo em /sinal, uma pasta que este container
# e o aplicativo enxergam os dois. Podia ser uma porta HTTP aqui dentro,
# mas ai este container viraria um servidor — com porta, rota e erro de
# rede para tratar — para receber um unico aviso sem conteudo.
#
# Sem cron de proposito: o cron da imagem alpine nao herda as variaveis
# do container e teria de recebe-las por um arquivo intermediario, o que
# esconderia a senha em disco por nada.

set -u

HORA_DO_BACKUP="${BACKUP_HORA:-03}"
PEDIDO=/sinal/pedido
ESTADO=/sinal/estado

mkdir -p /sinal

# Conta ao aplicativo o que esta acontecendo, para o botao saber se deve
# mostrar "atualizando..." ou o resultado.
anotar() {
  printf '%s\n%s\n' "$1" "$(date +%FT%T)" > "$ESTADO"
}

rodar() {
  anotar rodando
  if /scripts/backup.sh; then
    anotar ok
  else
    anotar falhou
    echo "[agendador] o backup falhou"
  fi
}

# Um backup ao subir, mas so se ainda nao houver o de hoje. Sem essa
# condicao, cada `docker compose up` durante o dia refaria o retrato
# inteiro — e sao varios por dia enquanto o codigo esta em obras.
if [ -d "/backups/$(date +%F)" ]; then
  echo "[agendador] o backup de hoje ja existe"
  anotar ok
else
  echo "[agendador] backup inicial"
  rodar
fi

# Dia em que o backup automatico ja rodou. Impede que ele dispare varias
# vezes durante a hora marcada, ja que a volta do laco e de segundos.
ultimo_automatico=$(date +%F)

echo "[agendador] de olho: pedido do aplicativo, ou ${HORA_DO_BACKUP}:00 todo dia"

while true; do
  # O pedido e apagado ANTES de comecar. Se fosse depois, um clique
  # durante um backup em andamento ficaria na fila e rodaria de novo
  # sem necessidade.
  if [ -f "$PEDIDO" ]; then
    rm -f "$PEDIDO"
    echo "[agendador] pedido do aplicativo"
    rodar
  fi

  hoje=$(date +%F)
  if [ "$(date +%H)" = "$HORA_DO_BACKUP" ] && [ "$hoje" != "$ultimo_automatico" ]; then
    ultimo_automatico="$hoje"
    echo "[agendador] hora marcada"
    rodar
  fi

  # Cinco segundos: rapido o bastante para o clique parecer imediato, e
  # devagar o bastante para nao custar nada. E o laco tambem e o que
  # acorda o backup depois de o computador voltar de uma suspensao —
  # um `sleep` de horas nao percebe que o mundo andou.
  sleep 5
done
