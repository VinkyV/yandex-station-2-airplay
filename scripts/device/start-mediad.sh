#!/bin/sh
# Разовый запуск демона колонки (в фоне, не привязан к ssh-сессии).
cd /data/quasar 2>/dev/null || cd /
MALLOC_ARENA_MAX=2 CA_CERTIFICATES=/system/vendor/quasar/ca-certificates.crt \
  exec /system/vendor/quasar/maind --mediad >> /data/quasar/mediad.log 2>&1
