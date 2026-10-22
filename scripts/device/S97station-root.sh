#!/bin/sh
# Автозапуск на Яндекс.Станции: отладка по сети, SSH, сторож обновлений,
# AirPlay-приёмник (доступен всегда) и распорядитель звука.
case "$1" in
  start)
    mount -o remount,rw / 2>/dev/null
    mkdir -p /data/quasar
    touch /data/quasar/activate_adb_quasmodrom /data/quasar/activate_network_adb

    T=/data/local/opt/airplay
    L=/data/local/opt/tools/lib/ld-musl-aarch64.so.1

    # SSH
    if [ -x "$T/bin/dropbear" ] && [ -f /data/local/etc/dropbear/host_ed25519 ]; then
      LD_LIBRARY_PATH="$T/lib:/data/local/opt/tools/lib" \
        "$L" "$T/bin/dropbear" -r /data/local/etc/dropbear/host_ed25519 \
        -p 2222 -P /run/dropbear.pid >/dev/null 2>&1
    fi

    # сторож обновлений
    [ -x /data/local/bin/watch-launchd.sh ] && \
      start-stop-daemon -S -b -m -p /run/watch-launchd.pid -x /bin/sh -- /data/local/bin/watch-launchd.sh

    # AirPlay: поднимаем после того, как появятся /data и звуковая карта
    [ -x /data/local/bin/boot-airplay.sh ] && \
      start-stop-daemon -S -b -m -p /run/boot-airplay.pid -x /bin/sh -- /data/local/bin/boot-airplay.sh
    ;;
  stop)
    pkill -f watch-launchd.sh 2>/dev/null
    pkill -f audio-owner.sh 2>/dev/null
    pkill -f airplay-daemon.sh 2>/dev/null
    pkill -f avahi-keeper.sh 2>/dev/null
    pkill -f "dropbear -r" 2>/dev/null
    ;;
esac
exit 0
