#!/bin/sh
# Запуск AirPlay 2 приёмника (внутри — свой лог, чтобы start-stop-daemon не съел вывод)
T2=/data/local/opt/airplay2
L=/data/local/opt/tools/lib/ld-musl-aarch64.so.1
export LD_LIBRARY_PATH=$T2/lib:/data/local/opt/tools/lib
export ALSA_CONFIG_PATH=/data/local/etc/asound.conf
export DBUS_SYSTEM_BUS_ADDRESS="$(cat /run/dbus/airplay.addr 2>/dev/null)"
exec $L $T2/bin/shairport-sync -c $T2/etc/shairport-sync.conf -v >> /data/local/tmp/shairport2.log 2>&1
