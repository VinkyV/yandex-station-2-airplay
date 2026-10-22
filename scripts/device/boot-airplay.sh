#!/bin/sh
# После загрузки: ждёт /data и звуковую карту, поднимает AirPlay 2 и распорядителя звука.
LOG=/data/local/tmp/boot-airplay.log
: >> "$LOG"
T2=/data/local/opt/airplay2
i=0
while [ $i -lt 120 ]; do
  [ -x "$T2/bin/shairport-sync" ] && [ -e /dev/snd/pcmC0D0p ] && break
  i=$((i+1)); sleep 1
done
echo "=== $(date): старт, ждал ${i}с ===" >> "$LOG"

/data/local/bin/airplay2-daemon.sh

if ! ps w | grep -q 'audio-owner\.sh'; then
  start-stop-daemon -S -b -m -p /run/audio-owner.pid -x /bin/sh -- /data/local/bin/audio-owner.sh
fi

echo "avahi=$(ps w | grep -c '[a]vahi-daemon') nqptp=$(ps w | grep -c '[n]qptp') shairport=$(ps w | grep -c '[s]hairport-sync -c /data/local/opt/airplay2')" >> "$LOG"
