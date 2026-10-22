#!/bin/sh
# Распорядитель звука для AirPlay 2: приёмник виден всегда, Алиса возвращается после сессии.
#   - идёт AirPlay (есть ESTABLISHED соединение с приёмником) -> демон колонки гасим
#   - сессия кончилась -> приёмник перезапускается (отпускает звук), демон колонки поднимается
#   - приёмник пропал -> поднимаем заново (не чаще раза в минуту)
# В AirPlay 2 приёмник слушает НЕ 5000, а случайный порт, поэтому сессию ловим по pid + lsof.
# Поиск процессов по подстроке командной строки через /proc (без ps+grep:
# шаблон легко совпадает с командной строкой того, кто его запустил).
pids_matching() {
  for d in /proc/[0-9]*; do
    pid=${d#/proc/}
    [ "$pid" = "$$" ] && continue
    [ "$pid" = "$PPID" ] && continue
    cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    case "$cmd" in *"$1"*) echo "$pid";; esac
  done
}

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


# Держит ли кто-нибудь устройство воспроизведения
pcm_busy() {
  for p in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
    for f in /proc/$p/fd/*; do
      t=$(readlink "$f" 2>/dev/null)
      case "$t" in *pcmC0D0p*) return 0;; esac
    done
  done
  return 1
}

# Ждём, пока устройство освободится (приёмник отпускает его не сразу)
wait_pcm_free() {
  i=0
  while pcm_busy && [ "$i" -lt 15 ]; do
    sleep 1; i=$((i+1))
  done
  [ "$i" -gt 0 ] && echo "$(date): ждал освобождения звука ${i}с" >> "$LOG"
}

start_mediad() {
  # Если экземпляров больше одного (лаунчер успевает поднять свой), они дерутся за звук
  # и Алиса молчит. Оставляем ровно один.
  PIDS=$(pids_matching '/system/vendor/quasar/maind --mediad')
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
    PID=$(pids_matching '/system/vendor/quasar/maind --mediad' | head -1)
    [ -n "$PID" ] && kill "$PID" 2>/dev/null
  else
    ps w | grep -q '[s]hairport-sync -c /data/local/opt/airplay2' || revive_receiver

    if [ "$AIRPLAY_WAS_ON" = "1" ]; then
      IDLE_COUNT=$((IDLE_COUNT+1))
      if [ "$IDLE_COUNT" -ge 1 ]; then
        echo "$(date): AirPlay закончился — возвращаю Алису" >> "$LOG"
        # приёмник отпускает устройство, а Алису поднимаем сразу: она нужнее,
        # приёмник всё равно вернётся в сеть за пару секунд
        for p in $(ps w | awk '/[s]hairport-sync -c \/data\/local\/opt\/airplay2/ {print $1}'); do kill "$p" 2>/dev/null; done
        wait_pcm_free
        start_mediad
        nohup /data/local/bin/airplay2-daemon.sh >/dev/null 2>&1 &
        echo "$(date): Алиса поднята, приёмник возвращается" >> "$LOG"
        AIRPLAY_WAS_ON=0
        IDLE_COUNT=0
      fi
    else
      start_mediad
    fi
  fi
  sleep 2
done
