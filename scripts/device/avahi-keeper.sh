#!/bin/sh
# Держит avahi живым: запускает в переднем плане и перезапускает, если упал.
T=/data/local/opt/airplay
L=/data/local/opt/tools/lib/ld-musl-aarch64.so.1
LOG=/data/local/tmp/avahi-keep.log
: > "$LOG"
while :; do
  ADDR=$(cat /run/dbus/airplay.addr 2>/dev/null)
  [ -n "$ADDR" ] || ADDR=$(cat /data/local/tmp/airplay.addr 2>/dev/null)
  # шина пропала (перезагрузка) — поднимаем заново
  if [ ! -S /run/dbus/airplay_bus ]; then
    mkdir -p /run/dbus
    LD_LIBRARY_PATH="$T/lib:/data/local/opt/tools/lib" \
      "$L" "$T/bin/dbus-daemon" --config-file=/data/local/etc/airplay-bus.conf \
      --fork --print-address=1 > /run/dbus/airplay.addr 2>/dev/null
    sleep 1
    ADDR=$(cat /run/dbus/airplay.addr 2>/dev/null)
  fi
  echo "=== $(date): запуск avahi, шина=$ADDR ===" >> "$LOG"
  DBUS_SYSTEM_BUS_ADDRESS="$ADDR" \
  LD_LIBRARY_PATH="$T/lib:/data/local/opt/tools/lib" \
    "$L" "$T/bin/avahi-daemon" --no-drop-root --no-chroot \
         -f "$T/etc/avahi/avahi-daemon.conf" >> "$LOG" 2>&1
  echo "=== $(date): avahi завершился, код $? ===" >> "$LOG"
  sleep 3
done
