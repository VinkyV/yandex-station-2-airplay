#!/bin/sh
# Управление источником AirPlay с самой колонки: пауза/плей, дальше, назад.
# Механизм: plist sendMediaRemoteCommand на канал событий сессии (см. обсуждение
# shairport-sync #2262). Команды отдаются через D-Bus-интерфейс приёмника.
#   airplay-ctl.sh next|prev|pause|play|toggle|stop|status
T2=/data/local/opt/airplay2
L=$T2/lib/ld-musl-aarch64.so.1
[ -x "$L" ] || L=/data/local/opt/tools/lib/ld-musl-aarch64.so.1
export LD_LIBRARY_PATH=$T2/lib:/data/local/opt/tools/lib
export DBUS_SYSTEM_BUS_ADDRESS="$(cat /run/dbus/airplay.addr 2>/dev/null)"
# --print-reply обязателен: без него dbus-send отправит вызов и тут же закроет
# соединение, а приёмник отменит обработчик — команда молча пропадёт.
D="$L --library-path $LD_LIBRARY_PATH $T2/bin/dbus-send --system --print-reply --dest=org.mpris.MediaPlayer2.ShairportSync /org/mpris/MediaPlayer2"

session() {
  for t in /proc/net/tcp /proc/net/tcp6; do
    [ -r "$t" ] || continue
    awk 'FNR>1 { split($2,a,":"); if (a[length(a)]=="1B58" && $4=="01") f=1 } END { exit(f?0:1) }' "$t" && return 0
  done
  return 1
}

case "$1" in
  next)   $D org.mpris.MediaPlayer2.Player.Next ;;
  prev)   $D org.mpris.MediaPlayer2.Player.Previous ;;
  pause)  $D org.mpris.MediaPlayer2.Player.Pause ;;
  play)   $D org.mpris.MediaPlayer2.Player.Play ;;
  toggle) $D org.mpris.MediaPlayer2.Player.PlayPause ;;
  stop)   $D org.mpris.MediaPlayer2.Player.Stop ;;
  status)
    if session; then echo "airplay|активен"; else echo "airplay|нет"; fi
    $L --library-path $LD_LIBRARY_PATH $T2/bin/dbus-send --system --print-reply \
      --dest=org.mpris.MediaPlayer2.ShairportSync /org/mpris/MediaPlayer2 \
      org.freedesktop.DBus.Properties.Get string:org.mpris.MediaPlayer2.Player \
      string:PlaybackStatus 2>/dev/null | tail -1 | sed 's/.*string //'
    ;;
  *) echo "использование: $0 next|prev|pause|play|toggle|stop|status" >&2; exit 2 ;;
esac
