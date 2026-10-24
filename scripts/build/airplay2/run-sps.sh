#!/bin/sh
# Запуск AirPlay 2 приёмника (свой лог, чтобы start-stop-daemon не съел вывод).
# Ровно один экземпляр: два приёмника — это тишина в управлении, потому что звук
# держит один, а D-Bus-имя (и, значит, команды) достаётся другому.
# Блокировка через mkdir: он атомарен, в отличие от проверки «есть ли процесс».
T2=/data/local/opt/airplay2
L=/data/local/opt/tools/lib/ld-musl-aarch64.so.1
LOG=/data/local/tmp/shairport2.log
LOCKDIR=/run/sps.lock

if ! mkdir "$LOCKDIR" 2>/dev/null; then
  OLD=$(cat "$LOCKDIR/pid" 2>/dev/null)
  if [ -n "$OLD" ] && [ -d "/proc/$OLD" ]; then
    echo "$(date): приёмник уже работает (pid $OLD), второй не запускаю" >> "$LOG"
    exit 0
  fi
  rm -rf "$LOCKDIR"
  mkdir "$LOCKDIR" 2>/dev/null || { echo "$(date): не удалось взять блокировку" >> "$LOG"; exit 0; }
fi
echo $$ > "$LOCKDIR/pid"

export LD_LIBRARY_PATH=$T2/lib:/data/local/opt/tools/lib
export ALSA_CONFIG_PATH=/data/local/etc/asound.conf
export DBUS_SESSION_BUS_ADDRESS="$(cat /run/dbus/airplay.addr 2>/dev/null)"
export DBUS_SYSTEM_BUS_ADDRESS="$(cat /run/dbus/airplay.addr 2>/dev/null)"
exec $L $T2/bin/shairport-sync -c $T2/etc/shairport-sync.conf -v >> "$LOG" 2>&1
