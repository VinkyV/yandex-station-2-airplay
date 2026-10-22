#!/bin/sh
# Поднимает AirPlay после загрузки: ждёт, пока появятся /data и звуковая карта,
# затем создаёт шину, avahi, приёмник и распорядителя звука.
LOG=/data/local/tmp/boot-airplay.log
: >> "$LOG"
T=/data/local/opt/airplay
L=/data/local/opt/tools/lib/ld-musl-aarch64.so.1

i=0
while [ $i -lt 120 ]; do
  [ -x "$T/bin/shairport-sync" ] && [ -e /dev/snd/pcmC0D0p ] && break
  i=$((i+1)); sleep 1
done
echo "=== $(date): старт, ждал ${i}с ===" >> "$LOG"

mkdir -p /run/dbus /run/avahi-daemon
if [ ! -S /run/dbus/airplay_bus ]; then
  LD_LIBRARY_PATH="$T/lib:/data/local/opt/tools/lib" \
    "$L" "$T/bin/dbus-daemon" --config-file=/data/local/etc/airplay-bus.conf \
    --fork --print-address=1 > /run/dbus/airplay.addr 2>&1
fi
sleep 1
cat /run/dbus/airplay.addr 2>/dev/null >> "$LOG"
echo "" >> "$LOG"

# avahi под присмотром (он читает адрес шины из /run/dbus/airplay.addr)
if ! ps w | grep -q '[a]vahi-daemon'; then
  start-stop-daemon -S -b -m -p /run/avahi-keeper.pid -x /bin/sh -- /data/local/bin/avahi-keeper.sh
fi
sleep 4

# приёмник
if ! ps w | grep -q '[s]hairport-sync -c'; then
  LD_LIBRARY_PATH="$T/lib:/data/local/opt/tools/lib" \
  ALSA_CONFIG_PATH=/data/local/etc/asound.conf \
  DBUS_SYSTEM_BUS_ADDRESS="$(cat /run/dbus/airplay.addr 2>/dev/null)" \
    nohup "$L" "$T/bin/shairport-sync" -c "$T/etc/shairport-sync.conf" \
    >> /data/local/tmp/shairport.log 2>&1 < /dev/null &
  sleep 4
fi

# распорядитель звука
if ! ps w | grep -q 'audio-owner\.sh'; then
  start-stop-daemon -S -b -m -p /run/audio-owner.pid -x /bin/sh -- /data/local/bin/audio-owner.sh
fi

echo "avahi=$(ps w | grep -c '[a]vahi-daemon') shairport=$(ps w | grep -c '[s]hairport-sync -c') порт=$(netstat -ln 2>/dev/null | grep -c ':5000')" >> "$LOG"
