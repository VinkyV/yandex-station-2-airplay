#!/bin/sh
# Управление AirPlay-приёмником на колонке с компьютера.
#
#   STATION=192.168.1.50 ./station-airplay.sh status
#   STATION=192.168.1.50 ./station-airplay.sh on|off|restart
#
# Переменные: STATION (обязательно), PORT (по умолчанию 2222),
#             KEY (по умолчанию ~/.ssh/id_ed25519)
set -u
: "${STATION:?укажите адрес колонки: STATION=192.168.1.50 $0 status}"
PORT="${PORT:-2222}"
KEY="${KEY:-$HOME/.ssh/id_ed25519}"

remote() {
  ssh -i "$KEY" -p "$PORT" -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new \
      -o BatchMode=yes "root@$STATION" "$1"
}

case "${1:-status}" in
  on)
    remote 'nohup /data/local/bin/boot-airplay.sh >/dev/null 2>&1 & sleep 2; echo "приёмник поднят"'
    ;;
  off)
    remote 'for p in $(ps w | awk "/[s]hairport-sync/ {print \$1}"); do kill "$p"; done
            for p in $(ps w | awk "/audio-owner\.sh/ {print \$1}"); do kill "$p"; done
            P=$(ps w | awk "/[m]aind --mediad/ {print \$1}" | head -1)
            [ -z "$P" ] && cd /data/quasar && \
              MALLOC_ARENA_MAX=2 CA_CERTIFICATES=/system/vendor/quasar/ca-certificates.crt \
              nohup /system/vendor/quasar/maind --mediad >>/data/quasar/mediad.log 2>&1 &
            echo "приёмник остановлен, звук у Алисы"'
    ;;
  restart)
    remote 'for p in $(ps w | awk "/[s]hairport-sync/ {print \$1}"); do kill "$p"; done; sleep 1
            /data/local/bin/airplay-daemon.sh; echo перезапущен'
    ;;
  status)
    remote 'echo "avahi: $(ps w | grep -c "[a]vahi-daemon")  shairport: $(ps w | grep -c "[s]hairport-sync -c")  mediad: $(ps w | grep -c "[m]aind --mediad")"
            echo "порт 5000: $(netstat -ln 2>/dev/null | grep -c ":5000")"
            echo "шина: $(cat /run/dbus/airplay.addr 2>/dev/null)"'
    ;;
  *)
    echo "использование: $0 on|off|restart|status" >&2
    exit 1
    ;;
esac
