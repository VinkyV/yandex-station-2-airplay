#!/bin/sh
# Переключение на AirPlay 2: гасим старую цепочку и поднимаем новую.
S=/data/local/tmp/switch-ap2.log
: > "$S"
say() { echo "$@" >> "$S"; }
say "=== $(date) switch to AP2 ==="

[ -f /run/audio-owner.pid ] && kill "$(cat /run/audio-owner.pid)" 2>/dev/null
for p in $(ps w | awk '/[a]udio-owner\.sh/ {print $1}'); do kill "$p" 2>/dev/null; done
for p in $(ps w | awk '/[s]hairport-sync -c/ {print $1}'); do kill "$p" 2>/dev/null; done
[ -f /run/nqptp.pid ] && kill "$(cat /run/nqptp.pid)" 2>/dev/null
for p in $(ps w | awk '/[n]qptp/ {print $1}'); do kill "$p" 2>/dev/null; done
sleep 3
say "после остановки: shairport=$(ps w | grep -c '[s]hairport-sync -c') nqptp=$(ps w | grep -c '[n]qptp') audio-owner=$(ps w | grep -c '[a]udio-owner.sh') mediad=$(ps w | grep -c '[m]aind --mediad')"

start-stop-daemon -S -b -m -p /run/boot-airplay.pid -x /bin/sh -- /data/local/bin/boot-airplay.sh
sleep 12
say "после старта: avahi=$(ps w | grep -c '[a]vahi-daemon') nqptp=$(ps w | grep -c '[n]qptp') shairport=$(ps w | grep -c '[s]hairport-sync -c /data/local/opt/airplay2') audio-owner=$(ps w | grep -c '[a]udio-owner.sh') mediad=$(ps w | grep -c '[m]aind --mediad')"
say "--- udp 319/320:"; netstat -lnu 2>/dev/null | grep -E ":319|:320" >> "$S"
say "--- log приёмника:"; tail -6 /data/local/tmp/shairport2.log >> "$S"
say "--- ap2-daemon:"; tail -3 /data/local/tmp/ap2-daemon.log >> "$S"
say "=== end ==="
