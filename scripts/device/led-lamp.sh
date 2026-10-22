#!/bin/sh
# Подсветка кольца: /dev/fb0, 89 пикселей по 4 байта (R,G,B,0).
# Кадры «дыхания» лежат готовыми файлами в /data/local/led/<цвет>.pat —
# считаются на маке (в busybox-awk нет cos(), а printf портит байты >127).
#   led-lamp.sh start [цвет]   — дыхание (по умолчанию violet)
#   led-lamp.sh solid [R G B]  — ровный свет
#   led-lamp.sh stop
FB=/dev/fb0
PIDF=/run/led-lamp.pid
LOG=/data/local/tmp/led-lamp.log
DIR=/data/local/led
NAME=${2:-violet}

case "$1" in
  start)
    [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null
    PAT="$DIR/$NAME.pat"
    [ -f "$PAT" ] || { echo "$(date): нет файла $PAT" >> "$LOG"; echo "нет файла $PAT" >&2; exit 1; }
    NF=$(( $(wc -c < "$PAT") / 356 ))
    # в файле уже заложен полный цикл (вверх и вниз), поэтому просто по кругу
    rm -f /run/led-lamp.stop
    ( i=0; while :; do
        [ -f /run/led-lamp.stop ] && break
        dd if="$PAT" of=$FB bs=356 skip=$i count=1 conv=notrunc 2>/dev/null
        i=$((i+1)); [ "$i" -ge "$NF" ] && i=0
        sleep 0.07
      done ) >/dev/null 2>&1 &
    echo $! > "$PIDF"
    echo "$(date): дыхание «$NAME», кадров $NF, pid=$(cat "$PIDF")" >> "$LOG"
    ;;
  solid)
    # $2 — имя готового кадра (solid_red, solid_white, …); кадры считаются на маке,
    # потому что busybox-awk портит байты больше 127
    [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null; rm -f "$PIDF"
    PAT="$DIR/${2:-solid_white}.pat"
    [ -f "$PAT" ] || { echo "нет файла $PAT" >&2; exit 1; }
    dd if="$PAT" of=$FB bs=356 count=1 conv=notrunc 2>/dev/null
    echo "$(date): ровный $2" >> "$LOG"
    ;;
  stop)
    touch /run/led-lamp.stop          # цикл выйдет сам после текущего кадра
    sleep 0.4
    [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null
    sleep 0.2
    rm -f "$PIDF"
    # гасим уже после того, как цикл перестал писать
    dd if=/dev/zero of=$FB bs=356 count=1 conv=notrunc 2>/dev/null
    rm -f /run/led-lamp.stop
    echo "$(date): выключено" >> "$LOG"
    ;;
  *) echo "использование: $0 start [цвет] | solid R G B | stop" >&2 ;;
esac
