#!/bin/sh
# Поднимает AirPlay-приёмник в фоне и НЕ трогает демон колонки.
# Адрес шины берём из /run/dbus/airplay.addr (его пишет boot-airplay.sh), иначе — из старого места.
T=/data/local/opt/airplay
L=/data/local/opt/tools/lib/ld-musl-aarch64.so.1
LOG=/data/local/tmp/airplay-daemon.log
echo "=== $(date): поднимаю приёмник ===" >> "$LOG"

mkdir -p /run/dbus /run/avahi-daemon

ADDR=$(cat /run/dbus/airplay.addr 2>/dev/null)
if [ -z "$ADDR" ] || [ ! -S /run/dbus/airplay_bus ]; then
  LD_LIBRARY_PATH="$T/lib:/data/local/opt/tools/lib" \
    "$L" "$T/bin/dbus-daemon" --config-file=/data/local/etc/airplay-bus.conf \
    --fork --print-address=1 > /run/dbus/airplay.addr 2>/dev/null
  sleep 1
  ADDR=$(cat /run/dbus/airplay.addr 2>/dev/null)
fi
echo "шина: $ADDR" >> "$LOG"

if ! ps w | grep -q '[a]vahi-daemon'; then
  start-stop-daemon -S -b -m -p /run/avahi-keeper.pid -x /bin/sh -- /data/local/bin/avahi-keeper.sh
  sleep 4
fi

if ! ps w | grep -q '[s]hairport-sync -c'; then
  LD_LIBRARY_PATH="$T/lib:/data/local/opt/tools/lib" \
  ALSA_CONFIG_PATH=/data/local/etc/asound.conf \
  DBUS_SYSTEM_BUS_ADDRESS="$ADDR" \
    nohup "$L" "$T/bin/shairport-sync" -c "$T/etc/shairport-sync.conf" \
    >> /data/local/tmp/shairport.log 2>&1 < /dev/null &
  sleep 4
fi

echo "avahi: $(ps w | grep -c '[a]vahi-daemon')  shairport: $(ps w | grep -c '[s]hairport-sync -c')  порт: $(netstat -ln 2>/dev/null | grep -c ':5000')" >> "$LOG"
