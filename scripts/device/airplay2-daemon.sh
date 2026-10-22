#!/bin/sh
# AirPlay 2: шина (если надо), avahi, nqptp (PTP 319/320) и приёмник shairport-sync.
T2=/data/local/opt/airplay2
TB=/data/local/opt/airplay
L=/data/local/opt/tools/lib/ld-musl-aarch64.so.1
LOG=/data/local/tmp/ap2-daemon.log
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

echo "=== $(date): airplay2-daemon ===" >> "$LOG"
mkdir -p /run/dbus /run/avahi-daemon

ADDR=$(cat /run/dbus/airplay.addr 2>/dev/null)
if [ -z "$ADDR" ] || [ ! -S /run/dbus/airplay_bus ]; then
  LD_LIBRARY_PATH="$TB/lib:/data/local/opt/tools/lib" \
    "$L" "$TB/bin/dbus-daemon" --config-file=/data/local/etc/airplay-bus.conf \
    --fork --print-address=1 > /run/dbus/airplay.addr 2>/dev/null
  sleep 1
fi

if ! ps w | grep -q '[a]vahi-daemon'; then
  start-stop-daemon -S -b -m -p /run/avahi-keeper.pid -x /bin/sh -- /data/local/bin/avahi-keeper.sh
  sleep 4
fi

# nqptp обязателен для AirPlay 2 и должен стартовать ДО приёмника.
# Экземпляр должен быть ровно один: два дерутся за порты 319/320 и ломают синхронизацию.
NQP=$(pids_matching /opt/airplay2/bin/nqptp)
NQN=$(printf '%s\n' "$NQP" | grep -c .)
if [ "$NQN" -gt 1 ]; then
  for p in $NQP; do kill -9 "$p" 2>/dev/null; done
  sleep 1
  echo "=== $(date): убрал дубли nqptp (было $NQN) ===" >> "$LOG"
  NQN=0
fi
if [ "$NQN" -eq 0 ]; then
  LD_LIBRARY_PATH="$T2/lib:/data/local/opt/tools/lib" \
    start-stop-daemon -S -b -m -p /run/nqptp.pid -x "$L" -- "$T2/bin/nqptp"
  sleep 1
fi

if [ -z "$(pids_matching '/opt/airplay2/bin/shairport-sync')" ]; then
  start-stop-daemon -S -b -m -p /run/shairport2.pid -x /bin/sh -- "$T2/bin/run-sps.sh"
  sleep 4
fi

echo "nqptp=$(pids_matching /opt/airplay2/bin/nqptp | wc -l) shairport=$(pids_matching '/opt/airplay2/bin/shairport-sync' | wc -l) avahi=$(ps w | grep -c '[a]vahi-daemon')" >> "$LOG"
