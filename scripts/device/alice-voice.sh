#!/bin/sh
# Слушатель локального IPC Алисы (127.0.0.1:9875).
# Читает кадры: 4 байта длины (LE) + protobuf. Внутри — финальный текст распознавания.
# Ищет фразы из /data/local/etc/voice-triggers.txt (по одной в строке, UTF-8)
# и пишет совпадения в лог. Действие подключается в hook().
LOG=/data/local/tmp/alice-voice.log
PAT=/data/local/etc/voice-triggers.txt
FRAME=/tmp/alice-frame.bin
STATE=/tmp/alice-voice.last
COOLDOWN=5

hook() { # $1 — сработавшая фраза
  # Пока только фиксируем. Сюда будет подключён запуск плеера «Звук».
  echo "$(date): СРАБОТАЛО «$1»" >> "$LOG"
}

while :; do
  # -u = только чтение: без этого socat закрывает соединение по EOF на stdin
  /data/local/bin/socat -u TCP:127.0.0.1:9875 - 2>/dev/null | while :; do
    SZ=$(dd bs=4 count=1 2>/dev/null | od -An -tu4 2>/dev/null | tr -d ' \n')
    case "$SZ" in ''|*[!0-9]*) break ;; esac
    [ "$SZ" -le 0 ] && break
    [ "$SZ" -gt 600000 ] && break
    dd bs="$SZ" count=1 of="$FRAME" 2>/dev/null
    [ -s "$PAT" ] || continue
    while read -r PATTERN; do
      [ -z "$PATTERN" ] && continue
      case "$PATTERN" in \#*) continue ;; esac
      if grep -aqF -- "$PATTERN" "$FRAME"; then
        NOW=$(date +%s)
        # одно и то же распознавание приходит в нескольких кадрах подряд —
        # помним последнюю сработавшую фразу и её время
        LAST_TS=0; LAST_PAT=""
        [ -f "$STATE" ] && { LAST_TS=$(cut -d'|' -f1 "$STATE"); LAST_PAT=$(cut -d'|' -f2 "$STATE"); }
        if [ "$PATTERN" = "$LAST_PAT" ] && [ $((NOW - LAST_TS)) -lt "$COOLDOWN" ]; then
          continue
        fi
        echo "$NOW|$PATTERN" > "$STATE"
        hook "$PATTERN"
      fi
    done < "$PAT"
  done
  echo "$(date): соединение с IPC потеряно, переподключаюсь" >> "$LOG"
  sleep 2
done
