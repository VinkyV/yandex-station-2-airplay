#!/bin/sh
# Установка musl-набора утилит на колонку (запускать на самой колонке от root).
#
#   adb push tools-aarch64-musl.tar.gz /data/local/tmp/
#   adb shell 'sh /data/local/tmp/install-tools.sh'
#
# Кладёт утилиты в /data/local/opt/tools, обёртки — в /data/local/bin.
T=/data/local/opt/tools
B=/data/local/bin
PKG=/data/local/tmp/tools-aarch64-musl.tar.gz
LOG=/data/local/tmp/install-tools.log
: > "$LOG"
exec >> "$LOG" 2>&1
echo "=== $(date) ==="

mkdir -p "$T" "$B"

if [ -f "$PKG" ]; then
  # busybox tar не умеет -z
  gzip -dc "$PKG" | tar -xf - -C "$T" && echo "архив распакован в $T" || echo "ошибка распаковки"
else
  echo "нет архива $PKG"
fi

for b in jq strace lsof tmux rsync dig host nslookup nc socat unzip zstd pv less tree file; do
  [ -x "$T/bin/$b" ] || continue
  printf '#!/bin/sh\nexport LD_LIBRARY_PATH="%s/lib"\nexport TERMINFO="%s/share/terminfo"\nexec "%s/lib/ld-musl-aarch64.so.1" "%s/bin/%s" "$@"\n' \
    "$T" "$T" "$T" "$T" "$b" > "$B/$b"
  chmod 755 "$B/$b"
done

echo "--- проверка ---"
"$B/jq" --version 2>&1
echo "=== готово ==="
