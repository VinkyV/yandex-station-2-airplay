#!/bin/sh
# Распорядитель звука: AirPlay виден всегда, Алиса возвращается после сессии.
#   - идёт AirPlay     -> демон колонки останавливается
#   - сессия кончилась -> приёмник перезапускается (отпускает устройство, но остаётся
#                         в сети), демон колонки поднимается обратно
#   - приёмник пропал   -> поднимается заново (не чаще раза в минуту)
LOG=/data/local/tmp/audio-owner.log
: >> "$LOG"
AIRPLAY_WAS_ON=0
IDLE_COUNT=0
LAST_REVIVE=0

playing() { netstat -tn 2>/dev/null | grep -q ':5000 .*ESTABLISHED'; }

start_mediad() {
  if ! ps w | grep -q '[m]aind --mediad'; then
    cd /data/quasar 2>/dev/null || cd /
    MALLOC_ARENA_MAX=2 CA_CERTIFICATES=/system/vendor/quasar/ca-certificates.crt \
      nohup /system/vendor/quasar/maind --mediad >> /data/quasar/mediad.log 2>&1 < /dev/null &
    echo "$(date): mediad поднят" >> "$LOG"
  fi
}

revive_receiver() {
  now=$(date +%s)
  if [ $((now - LAST_REVIVE)) -ge 60 ]; then
    LAST_REVIVE=$now
    echo "$(date): приёмник пропал — поднимаю заново" >> "$LOG"
    /data/local/bin/airplay-daemon.sh
  fi
}

while :; do
  if playing; then
    if [ "$AIRPLAY_WAS_ON" = "0" ]; then
      echo "$(date): AirPlay пошёл — освобождаю звук" >> "$LOG"
      AIRPLAY_WAS_ON=1
    fi
    IDLE_COUNT=0
    PID=$(ps w | awk '/[m]aind --mediad/ {print $1}' | head -1)
    [ -n "$PID" ] && kill "$PID" 2>/dev/null
  else
    # приёмник обязан жить всегда — иначе телефон его не увидит
    ps w | grep -q '[s]hairport-sync -c' || revive_receiver

    if [ "$AIRPLAY_WAS_ON" = "1" ]; then
      IDLE_COUNT=$((IDLE_COUNT+1))
      if [ "$IDLE_COUNT" -ge 2 ]; then
        echo "$(date): AirPlay закончился — перезапускаю приёмник, возвращаю Алису" >> "$LOG"
        for p in $(ps w | awk '/[s]hairport-sync/ {print $1}'); do kill "$p" 2>/dev/null; done
        sleep 1
        /data/local/bin/airplay-daemon.sh
        start_mediad
        AIRPLAY_WAS_ON=0
        IDLE_COUNT=0
      fi
    else
      start_mediad
    fi
  fi
  sleep 4
done
