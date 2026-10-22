#!/bin/sh
# Обработчик запросов панели. Запускается socat'ом на каждое соединение.
#   /                — страница статуса
#   /api/status      — JSON
#   /action?do=...&t=TOKEN — действия (нужен токен)
#   /log?name=...    — хвост лога

TOKENF=/data/local/etc/panel.token
TOKEN=$(cat "$TOKENF" 2>/dev/null)

read -r REQ
while read -r H; do
  H=$(printf '%s' "$H" | tr -d '\r')
  [ -z "$H" ] && break
done
REQ=$(printf '%s' "$REQ" | tr -d '\r')
PATHQ=$(printf '%s' "$REQ" | awk '{print $2}')
URLPATH=${PATHQ%%\?*}
QUERY=${PATHQ#*\?}
[ "$QUERY" = "$PATHQ" ] && QUERY=""

qval() {
  printf '%s' "$QUERY" | tr '&' '\n' | awk -F= -v k="$1" '$1==k {print substr($0, length(k)+2); exit}'
}

send() { # $1 = content-type, $2 = body
  printf 'HTTP/1.1 200 OK\r\nContent-Type: %s\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n' "$1"
  printf '%s' "$2"
}

pcount() { ps w 2>/dev/null | grep -c "$1"; }

pcm_owner() {
  for p in $(ls /proc | grep -E '^[0-9]+$'); do
    for f in /proc/$p/fd/*; do
      t=$(readlink "$f" 2>/dev/null)
      case "$t" in *pcmC0D0p*) cat /proc/$p/comm 2>/dev/null; return;; esac
    done
  done
  echo "свободно"
}

status_json() {
  SH=$(pcount '[s]hairport-sync -c')
  AV=$(pcount '[a]vahi-daemon')
  MD=$(pcount '[m]aind --mediad')
  UP=$(pcount '[u]pdatesd')
  P5=$(netstat -ln 2>/dev/null | grep -c ':5000')
  EST=$(netstat -tn 2>/dev/null | grep -c ':5000 .*ESTABLISHED')
  echo "{\"shairport\":$SH,\"avahi\":$AV,\"mediad\":$MD,\"updatesd\":$UP,\"port5000\":$P5,\"playing\":$EST,\"pcm\":\"$(pcm_owner)\"}"
}

row() { # $1 подпись, $2 значение, $3 ok/bad
  printf '<div class="row"><span>%s</span><b class="%s">%s</b></div>' "$1" "$3" "$2"
}
okbad() { [ "$1" -gt 0 ] 2>/dev/null && echo ok || echo bad; }

do_action() {
  A=$(qval do); T=$(qval t)
  if [ -z "$TOKEN" ] || [ "$T" != "$TOKEN" ]; then
    send "text/plain; charset=utf-8" "неверный или отсутствующий токен"
    return
  fi
  case "$A" in
    airplay-restart)
      for p in $(ps w | awk '/[s]hairport-sync/ {print $1}'); do kill "$p" 2>/dev/null; done
      sleep 1; /data/local/bin/airplay-daemon.sh >/dev/null 2>&1
      send "text/plain; charset=utf-8" "приёмник перезапущен" ;;
    airplay-off)
      for p in $(ps w | awk '/[s]hairport-sync/ {print $1}'); do kill "$p" 2>/dev/null; done
      send "text/plain; charset=utf-8" "приёмник остановлен, звук у Алисы" ;;
    mediad-restart)
      for p in $(ps w | awk '/[m]aind --mediad/ {print $1}'); do kill "$p" 2>/dev/null; done
      sleep 2
      cd /data/quasar 2>/dev/null || cd /
      MALLOC_ARENA_MAX=2 CA_CERTIFICATES=/system/vendor/quasar/ca-certificates.crt \
        nohup /system/vendor/quasar/maind --mediad >>/data/quasar/mediad.log 2>&1 </dev/null &
      send "text/plain; charset=utf-8" "медиа-демон перезапущен" ;;
    reboot)
      send "text/plain; charset=utf-8" "перезагрузка через 2 секунды"
      (sleep 2; sync; reboot) >/dev/null 2>&1 &
      ;;
    *)
      send "text/plain; charset=utf-8" "неизвестное действие" ;;
  esac
}

do_log() {
  N=$(qval name)
  case "$N" in
    airplay)  F=/data/local/tmp/shairport.log ;;
    owner)    F=/data/local/tmp/audio-owner.log ;;
    avahi)    F=/data/local/tmp/avahi-keep.log ;;
    boot)     F=/data/local/tmp/boot-airplay.log ;;
    updates)  F=/data/local/tmp/watch-launchd.log ;;
    *) send "text/plain; charset=utf-8" "нет такого лога"; return ;;
  esac
  send "text/plain; charset=utf-8" "$(tail -40 "$F" 2>/dev/null)"
}

page() {
  SH=$(pcount '[s]hairport-sync -c'); AV=$(pcount '[a]vahi-daemon')
  MD=$(pcount '[m]aind --mediad');     UP=$(pcount '[u]pdatesd')
  P5=$(netstat -ln 2>/dev/null | grep -c ':5000')
  EST=$(netstat -tn 2>/dev/null | grep -c ':5000 .*ESTABLISHED')
  OWN=$(pcm_owner)
  UP_T=$(cut -d. -f1 /proc/uptime)
  FW=$(cat /system/vendor/quasar/version_full 2>/dev/null)
  FREE=$(df -h /data 2>/dev/null | awk 'NR==2 {print $4}')
  TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
  [ -n "$TEMP" ] && TEMP="$((TEMP/1000)) °C" || TEMP="—"
  [ "$EST" -gt 0 ] && NOW="AirPlay играет" || NOW="Алиса"
  printf 'HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n'
  cat <<'EOF'
<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Станция Midi</title><style>
:root{color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;padding:24px;background:#111318;color:#e8eaed;font:16px/1.45 -apple-system,system-ui,sans-serif}
h1{font-size:20px;margin:0 0 4px}
.sub{color:#8b93a1;font-size:13px;margin-bottom:20px}
.card{background:#181b22;border:1px solid #262a33;border-radius:14px;padding:14px 16px;margin-bottom:14px}
.row{display:flex;justify-content:space-between;padding:6px 0;border-bottom:1px solid #22262e}
.row:last-child{border:0}
.ok{color:#5fd38d}.bad{color:#f2707b}.dim{color:#8b93a1}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
button{width:100%;padding:12px;border-radius:10px;border:1px solid #2d3340;background:#1f2430;color:#e8eaed;font-size:15px}
button:active{background:#2a3140}
button.warn{border-color:#553;color:#f0c674}
input{width:100%;padding:10px;border-radius:10px;border:1px solid #2d3340;background:#12151b;color:#e8eaed}
.small{font-size:13px;color:#8b93a1;margin-top:10px}
a{color:#79a8ff}
</style></head><body>
<h1>Яндекс Станция Midi</h1>
<div class="sub">root · AirPlay · обновления выключены</div>
<div class="card">
EOF
  printf '<div class="row"><span>сейчас звучит</span><b>%s</b></div>' "$NOW"
  row "приёмник AirPlay" "$SH" "$(okbad "$SH")"
  row "avahi (объявление в сети)" "$AV" "$(okbad "$AV")"
  row "демон Алисы (mediad)" "$MD" "$(okbad "$MD")"
  row "порт 5000" "$P5" "$(okbad "$P5")"
  row "обновлятор updatesd" "$UP" "$( [ "$UP" -eq 0 ] && echo ok || echo bad )"
  printf '<div class="row"><span>звук занят</span><b class="dim">%s</b></div>' "$OWN"
  printf '<div class="row"><span>прошивка</span><b class="dim">%s</b></div>' "$FW"
  printf '<div class="row"><span>свободно /data</span><b class="dim">%s</b></div>' "$FREE"
  printf '<div class="row"><span>температура</span><b class="dim">%s</b></div>' "$TEMP"
  printf '<div class="row"><span>аптайм</span><b class="dim">%s мин</b></div>' "$((UP_T/60))"
  cat <<'EOF'
</div>
<div class="card">
  <input id="tk" placeholder="токен доступа" autocomplete="off">
  <div class="grid" style="margin-top:10px">
    <button data-a="airplay-restart">Перезапустить AirPlay</button>
    <button data-a="airplay-off">Выключить AirPlay</button>
    <button data-a="mediad-restart">Поднять Алису</button>
    <button data-a="reboot" class="warn">Перезагрузить</button>
  </div>
  <div class="small">Действия только из домашней сети. Токен лежит в /data/local/etc/panel.token</div>
</div>
<div class="card">
  <div class="dim" style="margin-bottom:8px">Логи</div>
  <div class="grid">
    <button data-log="airplay">приёмник</button>
    <button data-log="owner">распорядитель</button>
    <button data-log="avahi">avahi</button>
    <button data-log="boot">загрузка</button>
  </div>
  <pre id="out" class="small" style="white-space:pre-wrap;margin-top:12px"></pre>
</div>
<script>
var tk=document.getElementById('tk'),out=document.getElementById('out');
tk.value=localStorage.getItem('panel-token')||'';
tk.oninput=function(){localStorage.setItem('panel-token',tk.value)};
function show(t){out.textContent=t}
document.querySelectorAll('[data-a]').forEach(function(b){b.onclick=function(){
  if(b.dataset.a==='reboot'&&!confirm('Перезагрузить колонку?'))return;
  show('…');
  fetch('/action?do='+b.dataset.a+'&t='+encodeURIComponent(tk.value)).then(function(r){return r.text()}).then(show).catch(function(e){show('ошибка: '+e)});
}});
document.querySelectorAll('[data-log]').forEach(function(b){b.onclick=function(){
  show('…');
  fetch('/log?name='+b.dataset.log).then(function(r){return r.text()}).then(show).catch(function(e){show('ошибка: '+e)});
}});
setInterval(function(){fetch('/api/status').then(function(r){return r.json()}).then(function(s){
  document.title=(s.playing?'▶ ':'')+'Станция Midi';}).catch(function(){})},5000);
</script></body></html>
EOF
}

case "$URLPATH" in
  /api/status) send "application/json" "$(status_json)" ;;
  /action)     do_action ;;
  /log)        do_log ;;
  /)           page ;;
  *)           send "text/plain; charset=utf-8" "не найдено" ;;
esac
