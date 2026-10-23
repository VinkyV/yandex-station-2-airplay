#!/bin/sh
# Блокировка обновлений: заглушка применителя OTA + неизменяемые маркеры ADB.
# Обратимо: оригинал остаётся рядом как device_ota_update.sh.orig,
# разрешить штатное обновление — touch /data/local/allow_ota
set -u
Q=/system/vendor/quasar
BACKUP=/data/local/backup
STUB=$Q/device_ota_update.sh
ORIG=$Q/device_ota_update.sh.orig
ALLOW=/data/local/allow_ota

mount -o remount,rw / 2>/dev/null
mkdir -p "$BACKUP"

# 1. бэкапы (идемпотентно)
[ -f "$BACKUP/device_ota_update.sh.orig" ] || cp -a "$STUB" "$BACKUP/device_ota_update.sh.orig"
[ -f "$BACKUP/ota_script.pub.orig" ] || cp -a "$Q/ota_script.pub" "$BACKUP/ota_script.pub.orig"

# 2. оригинал рядом + обёртка
[ -f "$ORIG" ] || cp -a "$STUB" "$ORIG"
cat > "$STUB" <<'EOF'
#!/bin/sh
# ОБНОВЛЕНИЯ ЗАБЛОКИРОВАНЫ. Оригинал: device_ota_update.sh.orig
# Разрешить штатное применение OTA: touch /data/local/allow_ota
LOG=/data/local/tmp/ota-blocked.log
ALLOW=/data/local/allow_ota
ORIG=/system/vendor/quasar/device_ota_update.sh.orig

echo "$(date): запрос применения OTA, аргументы: $*" >> "$LOG"
if [ -f "$ALLOW" ]; then
  echo "$(date): найден $ALLOW — выполняю оригинал" >> "$LOG"
  exec "$ORIG" "$@"
fi
echo "$(date): отклонено" >> "$LOG"
echo "OTA заблокировано. Разрешить: touch $ALLOW" >&2
exit 1
EOF
chmod 755 "$STUB"
sh -n "$STUB" || { echo "ошибка синтаксиса в обёртке" >&2; exit 1; }

# 3. маркеры делаем неизменяемыми
touch /data/quasar/activate_adb_quasmodrom /data/quasar/activate_network_adb 2>/dev/null
chattr +i /data/quasar/activate_adb_quasmodrom /data/quasar/activate_network_adb 2>/dev/null

sync
echo "готово: применитель заглушён, маркеры неизменяемы"
lsattr /data/quasar/activate_* 2>/dev/null
