#!/bin/sh
# Проверить, что колонка «в порядке» после восстановления или ребута.
#
#   restore/verify.sh
#
# Ничего не меняет: только читает. Код возврата 1, если что-то не так.
#
# Почему проверка идёт отдельным скриптом на устройстве, а не одной длинной
# ssh-командой:
# 1) приёмник, avahi и nqptp запускаются через musl-загрузчик, поэтому
#    readlink /proc/<pid>/exe у них показывает ld-musl, а не саму программу;
# 2) текст проверки содержит имена процессов в собственной командной строке
#    и считает себя — «mediad: 2 копии» было ровно этим.
set -u

# Адрес колонки — обязательный параметр: в публичной версии никаких сетей по умолчанию.
#   STATION=<IP> KEY=~/.ssh/station sh verify.sh
HOST=${STATION:?укажите адрес колонки: STATION=<ip> sh verify.sh}
PORT=${PORT:-2222}
KEY=${KEY:-$HOME/.ssh/station}
SSH="ssh -i $KEY -p $PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=8 root@$HOST"

OK=0; BAD=0
pass() { printf '  ок    %s\n' "$*"; OK=$((OK+1)); }
fail() { printf '  НЕТ   %s\n' "$*"; BAD=$((BAD+1)); }

printf '== колонка %s:%s ==\n' "$HOST" "$PORT"

if ! $SSH 'echo ok' >/dev/null 2>&1; then
    printf '  НЕТ   SSH не отвечает — дальше проверять нечего\n'
    exit 1
fi
pass "SSH по ключу"

# проверка уезжает на колонку файлом: никаких кавычек и самопересечений
PROBE=$(mktemp); OUT=$(mktemp)
trap 'rm -f "$PROBE" "$OUT"' EXIT

cat > "$PROBE" <<'REMOTE'
SELF=$$; PARENT=$PPID
nqptp=0; shair=0; avahi=0; mediad=0; voice=0
for p in /proc/[0-9]*; do
    pid=${p#/proc/}
    [ "$pid" = "$SELF" ] && continue
    [ "$pid" = "$PARENT" ] && continue
    c=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null) || continue
    case "$c" in
        */airplay2/bin/nqptp\ *)         nqptp=$((nqptp+1)) ;;
        */airplay2/bin/shairport-sync*)  shair=$((shair+1)) ;;
        *avahi-daemon:*)                 avahi=$((avahi+1)) ;;
        */system/vendor/quasar/maind\ --mediad*) mediad=$((mediad+1)) ;;
        */data/local/bin/alice-voice.sh*) voice=$((voice+1)) ;;
    esac
done

echo "marker=$([ -f /data/quasar/activate_network_adb ] && echo 1 || echo 0)"
echo "jq=$([ -x /data/local/opt/tools/bin/jq ] && echo yes || echo no)"
echo "nqptp=$nqptp"
echo "shairport=$shair"
echo "avahi=$avahi"
echo "mediad=$mediad"
echo "voice=$voice"
echo "led=$(ls /data/local/led/*.pat 2>/dev/null | wc -l | tr -d ' ')"
echo "updatesd=$(grep -c updatesd /system/vendor/quasar/launch.json 2>/dev/null | tr -d ' ')"
echo "ota_wrapper=$(grep -q allow_ota /system/vendor/quasar/device_ota_update.sh 2>/dev/null && echo yes || echo no)"
echo "zvukd=$([ -x /data/local/opt/zvuk/bin/zvukd ] && echo yes || echo no)"
echo "sock_zvukd=$([ -S /run/zvukd.sock ] && echo yes || echo no)"
echo "panel=$(netstat -ln 2>/dev/null | grep -q ':8081 ' && echo yes || echo no)"
echo "ap2=$(netstat -ln 2>/dev/null | grep -q ':7000 ' && echo yes || echo no)"
echo "free_mb=$(df -k /data | awk 'NR==2 {print int($4/1024)}')"
REMOTE

if ! cat "$PROBE" | $SSH 'cat > /data/local/tmp/verify-state.sh && sh /data/local/tmp/verify-state.sh' > "$OUT" 2>/dev/null; then
    printf '  НЕТ   проверку не удалось выполнить на устройстве\n'
    exit 1
fi
R=$(cat "$OUT")

get() { printf '%s\n' "$R" | sed -n "s/^$1=//p" | head -1; }

[ "$(get marker)" = "1" ] && pass "метка сетевого ADB на месте" || fail "нет /data/quasar/activate_network_adb — после ребута SSH может не подняться"
[ "$(get jq)" = "yes" ] && pass "набор утилит в /data/local/opt/tools" || fail "нет jq — набор утилит не развёрнут"
[ "$(get nqptp)" = "1" ] && pass "nqptp: один экземпляр" || fail "nqptp: $(get nqptp) (должен быть ровно 1)"
[ "$(get ap2)" = "yes" ] && pass "AirPlay 2 слушает 7000" || fail "порт 7000 не слушается — приёмник не поднялся"
[ "$(get shairport)" != "0" ] && pass "приёмник в процессах" || fail "процесса shairport-sync нет"
[ "$(get avahi)" != "0" ] && pass "avahi работает" || fail "avahi не запущен — колонку не видно в сети"
case "$(get mediad)" in
    1) pass "Алиса: один mediad" ;;
    0) fail "mediad не запущен — Алиса молчит" ;;
    *) fail "mediad: $(get mediad) копий (дерутся за звук)" ;;
esac
[ "$(get led)" -ge 1 ] 2>/dev/null && pass "кадры подсветки: $(get led)" || fail "нет кадров в /data/local/led"
# у слушателя всегда есть подshell с той же командной строкой: 2 совпадения = одна копия
case "$(get voice)" in
    2) pass "слушатель голоса: одна копия" ;;
    0) fail "слушатель голоса не запущен" ;;
    *) fail "слушатель голоса: $(get voice) совпадений — похоже на копии (двойные срабатывания)" ;;
esac
[ "$(get updatesd)" = "0" ] && pass "обновления заморожены (updatesd нет в launch.json)" || fail "updatesd в launch.json — обновления могут приехать"
[ "$(get ota_wrapper)" = "yes" ] && pass "применитель OTA — заглушка с обходом" || fail "device_ota_update.sh не заглушка (второй слой заморозки)"
[ "$(get zvukd)" = "yes" ] && pass "плеер Звука установлен" || fail "плеера Звука нет (не критично, если не нужен)"
[ "$(get free_mb)" -gt 20 ] 2>/dev/null && pass "место на /data: $(get free_mb) МБ" || fail "на /data мало места: $(get free_mb) МБ"

# панель проверяем снаружи — живой сервер ответит 200
# панель на socat бывает занята соседним запросом — три попытки
# (однострочный python: heredoc внутри $( ) в busybox-подобном sh ведёт себя непредсказуемо)
CODE=000
for _try in 1 2 3; do
    CODE=$(python3 -c 'import sys,urllib.request
try:
    print(urllib.request.urlopen("http://%s:8081/api/status" % sys.argv[1], timeout=6).status)
except Exception:
    print(000)' "$HOST" 2>/dev/null) || CODE=000
    [ "$CODE" = "200" ] && break
    sleep 2
done
[ "$CODE" = "200" ] && pass "панель отвечает /api/status" || fail "панель не ответила на :8081/api/status (код $CODE)"

printf '\n== итог: ок %s, проблем %s ==\n' "$OK" "$BAD"
[ "$BAD" = "0" ] || exit 1
