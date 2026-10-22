#!/bin/sh
# AirPlay 2: шина (если надо), avahi, nqptp (PTP 319/320) и приёмник shairport-sync.
T2=/data/local/opt/airplay2
TB=/data/local/opt/airplay
L=/data/local/opt/tools/lib/ld-musl-aarch64.so.1
LOG=/data/local/tmp/ap2-daemon.log
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

# nqptp обязателен для AirPlay 2 и должен стартовать ДО приёмника
if ! ps w | grep -q '[n]qptp'; then
  LD_LIBRARY_PATH="$T2/lib:/data/local/opt/tools/lib" \
    start-stop-daemon -S -b -m -p /run/nqptp.pid -x "$L" -- "$T2/bin/nqptp"
  sleep 1
fi

if ! ps w | grep -q '[s]hairport-sync -c /data/local/opt/airplay2'; then
  start-stop-daemon -S -b -m -p /run/shairport2.pid -x /bin/sh -- "$T2/bin/run-sps.sh"
  sleep 4
fi

echo "nqptp=$(ps w | grep -c '[n]qptp') shairport=$(ps w | grep -c '[s]hairport-sync -c /data/local/opt/airplay2') avahi=$(ps w | grep -c '[a]vahi-daemon')" >> "$LOG"
