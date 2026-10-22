#!/bin/sh
# Распорядитель звука для AirPlay 2: приёмник виден всегда, Алиса возвращается после сессии.
#   - идёт AirPlay (есть ESTABLISHED соединение с приёмником) -> демон колонки гасим
#   - сессия кончилась -> приёмник перезапускается (отпускает звук), демон колонки поднимается
#   - приёмник пропал -> поднимаем заново (не чаще раза в минуту)
# В AirPlay 2 приёмник слушает НЕ 5000, а случайный порт, поэтому сессию ловим по pid + lsof.
LOG=/data/local/tmp/audio-owner.log
L=/data/local/opt/tools/lib/ld-musl-aarch64.so.1
T2=/data/local/opt/airplay2
: >> "$LOG"
AIRPLAY_WAS_ON=0
IDLE_COUNT=0
LAST_REVIVE=0

sp_pid() { ps w | awk '/[s]hairport-sync -c \/data\/local\/opt\/airplay2/ {print $1}' | head -1; }

playing() {
  P=$(sp_pid)
  [ -z "$P" ] && return 1
  LD_LIBRARY_PATH=/data/local/opt/tools/lib "$L" /data/local/opt/tools/bin/lsof -nP -a -p "$P" -i TCP -s TCP:ESTABLISHED 2>/dev/null | grep -q ESTABLISHED
}

start_mediad() {
  # Если экземпляров больше одного (лаунчер успевает поднять свой), они дерутся за звук
  # и Алиса молчит. Оставляем ровно один.
  PIDS=$(ps w | awk '/[m]aind --mediad/ {print $1}')
  N=$(printf '%s\n' "$PIDS" | grep -c .)
  if [ "$N" -gt 1 ]; then
    for p in $PIDS; do kill -9 "$p" 2>/dev/null; done
    sleep 2
    echo "$(date): убрал дубли mediad (было $N)" >> "$LOG"
    N=0
  fi
  if [ "$N" -eq 0 ]; then
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
    /data/local/bin/airplay2-daemon.sh
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
    ps w | grep -q '[s]hairport-sync -c /data/local/opt/airplay2' || revive_receiver

    if [ "$AIRPLAY_WAS_ON" = "1" ]; then
      IDLE_COUNT=$((IDLE_COUNT+1))
      if [ "$IDLE_COUNT" -ge 2 ]; then
        echo "$(date): AirPlay закончился — перезапускаю приёмник, возвращаю Алису" >> "$LOG"
        for p in $(ps w | awk '/[s]hairport-sync -c \/data\/local\/opt\/airplay2/ {print $1}'); do kill "$p" 2>/dev/null; done
        sleep 1
        /data/local/bin/airplay2-daemon.sh
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
