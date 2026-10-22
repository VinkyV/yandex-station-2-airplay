#!/bin/sh
# Сторож: если облако вернёт задачу обновления — убирает её обратно.
REF=/data/local/etc/launch.no-updates.json
TARGET=/system/vendor/quasar/launch.json
while :; do
  if grep -q updatesd "$TARGET" 2>/dev/null; then
    mount -o remount,rw / 2>/dev/null
    cp "$REF" "$TARGET" && sync
    pkill -f "maind --updatesd" 2>/dev/null
    echo "$(date): updatesd убран заново" >> /data/local/watch-launchd.log
  fi
  sleep 60
done
