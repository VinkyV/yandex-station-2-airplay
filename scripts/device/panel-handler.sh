#!/bin/sh
# Обработчик запросов панели. Запускается socat'ом на каждое соединение.
#   /                      — страница
#   /api/status            — JSON со всем состоянием
#   /action?do=…&t=TOKEN   — действия (нужен токен)
#   /log?name=…            — хвост лога

T=/data/local/opt/airplay
L=/data/local/opt/tools/lib/ld-musl-aarch64.so.1
export LD_LIBRARY_PATH="$T/lib:/data/local/opt/tools/lib"
export ALSA_CONFIG_PATH=/data/local/etc/asound.conf

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

send() {
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
  echo "Свободно"
}

# Громкость: проверено на слух — громкостью управляют КАНАЛЫ усилителя (numid=2,3),
# а «мастер» (numid=1) стоит на заводском 214 и почти не влияет. Поэтому ползунок
# двигает только каналы: 100% = заводские 159 (обычная громкость колонки), 0% = тишина.
# Ниже ~25% звука практически нет — это особенность железа, а не ползунка.
AMP_MASTER=1
AMP_CH1=2
AMP_CH2=3
STOCK_MASTER=214
STOCK_CH=159

raw_get() { "$L" "$T/bin/amixer" cget numid=$1 2>/dev/null | sed -n 's/^ *: values=\([0-9]*\).*/\1/p' | head -1; }
raw_set() { "$L" "$T/bin/amixer" -q cset numid=$1 "$2" >/dev/null 2>&1; }

volume() {
  v=$(raw_get $AMP_CH1)
  if [ -z "$v" ]; then
    "$L" "$T/bin/amixer" sget Master 2>/dev/null | sed -n 's/.*\[\([0-9]*\)%\].*/\1/p' | head -1
    return
  fi
  p=$(( (v * 100 + STOCK_CH / 2) / STOCK_CH ))
  [ "$p" -lt 0 ] && p=0
  [ "$p" -gt 100 ] && p=100
  echo "$p"
}

set_volume() {
  c=$(( ($1 * STOCK_CH + 50) / 100 ))
  raw_set $AMP_MASTER $STOCK_MASTER
  raw_set $AMP_CH1 "$c"
  raw_set $AMP_CH2 "$c"
}

status_json() {
  SP=$(ps w | awk '/[s]hairport-sync/ {print $1}' | head -1)
  SH=0; [ -n "$SP" ] && SH=1
  AV=$(pcount '[a]vahi-daemon')
  NQ=$(pcount '[n]qptp')
  MD=$(pcount '[m]aind --mediad')
  UP=$(pcount '[u]pdatesd')
  EST=0; LPORT="—"
  if [ -n "$SP" ]; then
    LS=$(LD_LIBRARY_PATH="$T/lib:/data/local/opt/tools/lib" "$L" /data/local/opt/tools/bin/lsof -nP -a -p "$SP" -i TCP 2>/dev/null)
    EST=$(printf '%s\n' "$LS" | grep -c ESTABLISHED)
    LPORT=$(printf '%s\n' "$LS" | awk '/LISTEN/ {print $9}' | sed 's/.*://' | head -1)
    [ -z "$LPORT" ] && LPORT="—"
  fi
  V=$(volume); [ -z "$V" ] && V=0
  UPT=$(cut -d. -f1 /proc/uptime)
  FREE=$(df -h /data 2>/dev/null | awk 'NR==2 {print $4}')
  TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
  [ -n "$TEMP" ] && TEMP=$((TEMP/1000)) || TEMP=0
  IP=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
  WST=$(wpa_cli -i wlan0 status 2>/dev/null)
  SSID=$(printf '%s\n' "$WST" | awk -F= '/^ssid=/ {print substr($0,6); exit}')
  FRQ=$(printf '%s\n' "$WST" | awk -F= '/^freq=/ {print $2; exit}')
  BAND=""
  if [ -n "$FRQ" ]; then
    if [ "$FRQ" -ge 4000 ] 2>/dev/null; then BAND="5 ГГц"; else BAND="2.4 ГГц"; fi
  fi
  FW=$(cat /system/vendor/quasar/version_full 2>/dev/null)
  echo "{\"fw\":\"${FW:-—}\",\"shairport\":$SH,\"nqptp\":$NQ,\"avahi\":$AV,\"mediad\":$MD,\"updatesd\":$UP,\"listen\":\"${LPORT}\",\"playing\":$EST,\"volume\":${V:-0},\"pcm\":\"$(pcm_owner)\",\"uptime\":$((UPT/60)),\"free\":\"${FREE:--}\",\"temp\":$TEMP,\"ip\":\"${IP:-—}\",\"ssid\":\"${SSID:-—}\",\"band\":\"${BAND:-—}\"}"
}

do_action() {
  A=$(qval do)
  case "$A" in
    airplay-restart)
      for p in $(ps w | awk '/[s]hairport-sync/ {print $1}'); do kill "$p" 2>/dev/null; done
      sleep 1; /data/local/bin/airplay-daemon.sh >/dev/null 2>&1
      send "text/plain; charset=utf-8" "приёмник перезапущен" ;;
    airplay-off)
      for p in $(ps w | awk '/[s]hairport-sync/ {print $1}'); do kill "$p" 2>/dev/null; done
      send "text/plain; charset=utf-8" "приёмник остановлен, звук у Алисы" ;;
    avahi-restart)
      for p in $(ps w | awk '/[a]vahi-daemon/ {print $1}'); do kill "$p" 2>/dev/null; done
      send "text/plain; charset=utf-8" "avahi перезапущен — сторож поднимает его за пару секунд" ;;
    mediad-restart)
      for p in $(ps w | awk '/[m]aind --mediad/ {print $1}'); do kill "$p" 2>/dev/null; done
      sleep 2
      cd /data/quasar 2>/dev/null || cd /
      MALLOC_ARENA_MAX=2 CA_CERTIFICATES=/system/vendor/quasar/ca-certificates.crt \
        nohup /system/vendor/quasar/maind --mediad >>/data/quasar/mediad.log 2>&1 </dev/null &
      send "text/plain; charset=utf-8" "медиа-демон перезапущен" ;;
    volume)
      V=$(qval v)
      case "$V" in ''|*[!0-9]*) send "text/plain; charset=utf-8" "плохое значение"; return;; esac
      [ "$V" -gt 100 ] && V=100
      set_volume "$V"
      send "text/plain; charset=utf-8" "Громкость $V%" ;;
    reboot)
      send "text/plain; charset=utf-8" "перезагрузка через 2 секунды"
      (sleep 2; sync; reboot) >/dev/null 2>&1 &
      ;;
    *) send "text/plain; charset=utf-8" "неизвестное действие" ;;
  esac
}

do_log() {
  N=$(qval name)
  case "$N" in
    airplay) F=/data/local/tmp/shairport.log ;;
    owner)   F=/data/local/tmp/audio-owner.log ;;
    avahi)   F=/data/local/tmp/avahi-keep.log ;;
    boot)    F=/data/local/tmp/boot-airplay.log ;;
    updates) F=/data/local/tmp/watch-launchd.log ;;
    panel)   F=/data/local/tmp/panel.log ;;
    *) send "text/plain; charset=utf-8" "нет такого лога"; return ;;
  esac
  send "text/plain; charset=utf-8" "$(tail -40 "$F" 2>/dev/null)"
}

page() {
  printf 'HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n'
  cat <<'EOF'
<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Станция Midi</title><style>
:root{color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;padding:24px;background:#111318;color:#e8eaed;font:16px/1.45 -apple-system,system-ui,sans-serif}
h1{font-size:20px;margin:0 0 4px}
.sub{color:#8b93a1;font-size:13px;margin-bottom:18px}
.card{background:#181b22;border:1px solid #262a33;border-radius:14px;padding:14px 16px;margin-bottom:14px}
.row{display:flex;justify-content:space-between;gap:12px;padding:7px 0;border-bottom:1px solid #22262e}
.row:last-child{border:0}
.ok{color:#5fd38d}.bad{color:#f2707b}.dim{color:#8b93a1}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
button{width:100%;padding:12px;border-radius:10px;border:1px solid #2d3340;background:#1f2430;color:#e8eaed;font-size:15px}
button:active{background:#2a3140}
button.warn{border-color:#553;color:#f0c674}
input[type=text]{width:100%;padding:10px;border-radius:10px;border:1px solid #2d3340;background:#12151b;color:#e8eaed}
input[type=range]{width:100%;accent-color:#79a8ff}
.small{font-size:13px;color:#8b93a1;margin-top:10px}
.hdr{display:flex;justify-content:space-between;align-items:baseline;margin-bottom:6px}
pre{white-space:pre-wrap;margin:10px 0 0}
</style></head><body>
<h1>Яндекс Станция Midi</h1>
<div class="sub">Root · AirPlay · Обновления выключены</div>

<div class="card">
  <div class="hdr"><span class="dim">Сейчас звучит</span><b id="now">…</b></div>
  <div class="row"><span>Приёмник AirPlay</span><b id="v-shairport" class="dim">…</b></div>
  <div class="row"><span>Avahi (объявление в сети)</span><b id="v-avahi" class="dim">…</b></div>
  <div class="row"><span>Демон Алисы</span><b id="v-mediad" class="dim">…</b></div>
  <div class="row"><span>Слушает порт</span><b id="v-port" class="dim">…</b></div>
  <div class="row"><span>Nqptp (AirPlay 2)</span><b id="v-nqptp" class="dim">…</b></div>
  <div class="row"><span>Обновлятор updatesd</span><b id="v-upd" class="dim">…</b></div>
  <div class="row"><span>Звук занят</span><b id="v-pcm" class="dim">…</b></div>
</div>

<div class="card">
  <div class="hdr"><span class="dim">Громкость</span><b id="v-vol">…</b></div>
  <input id="vol" type="range" min="0" max="100" step="1" value="50">
  <div class="small">Отпусти ползунок — применится</div>
</div>

<div class="card">
  <div class="row"><span>Сеть</span><b id="v-net" class="dim">…</b></div>
  <div class="row"><span>Прошивка</span><b id="v-fw" class="dim">…</b></div>
  <div class="row"><span>Свободно /data</span><b id="v-free" class="dim">…</b></div>
  <div class="row"><span>Температура</span><b id="v-temp" class="dim">…</b></div>
  <div class="row"><span>Аптайм</span><b id="v-uptime" class="dim">…</b></div>
</div>

<div class="card">
  <div class="grid">
    <button data-a="airplay-restart">Перезапустить AirPlay</button>
    <button data-a="airplay-off">Выключить AirPlay</button>
    <button data-a="avahi-restart">Перезапустить avahi</button>
    <button data-a="mediad-restart">Поднять Алису</button>
    <button data-a="reboot" class="warn">Перезагрузить</button>
  </div>
  <div class="small">Только домашняя сеть</div>
</div>

<div class="card">
  <div class="dim">Логи</div>
  <div class="grid" style="margin-top:8px">
    <button data-log="airplay">Приёмник</button>
    <button data-log="owner">Распорядитель</button>
    <button data-log="avahi">Avahi</button>
    <button data-log="boot">Загрузка</button>
    <button data-log="updates">Обновления</button>
    <button data-log="panel">Панель</button>
  </div>
  <pre id="out" class="small"></pre>
</div>

<script>
var out=document.getElementById('out'),
    vol=document.getElementById('vol'),volLabel=document.getElementById('v-vol'),
    volBusy=false;

function show(t){out.textContent=t}
function cls(el,good){el.className=good?'ok':'bad'}

function paint(s){
  document.getElementById('now').textContent=s.playing?'AirPlay играет':'Алиса';
  var m={shairport:'v-shairport',avahi:'v-avahi',mediad:'v-mediad'};
  for(var k in m){
    var el=document.getElementById(m[k]);
    el.textContent=s[k]>0?'Работает':'Нет';
    cls(el,s[k]>0);
  }
  var nq=document.getElementById('v-nqptp');
  nq.textContent=s.nqptp>0?'Работает':'Нет';cls(nq,s.nqptp>0);
  var pp=document.getElementById('v-port');
  pp.textContent=s.listen||'—';pp.className='dim';
  var md=document.getElementById('v-mediad');
  if(s.playing&&s.mediad===0){md.textContent='Уступлен AirPlay';md.className='dim'}
  var u=document.getElementById('v-upd');
  u.textContent=s.updatesd>0?'Включён':'Выключен';cls(u,s.updatesd===0);
  var p=document.getElementById('v-pcm');p.textContent=s.pcm||'—';p.className='dim';
  if(!volBusy){vol.value=s.volume;volLabel.textContent=s.volume+'%'}
  document.getElementById('v-net').textContent=(s.ip||'—')+' · '+(s.ssid||'—')+' · '+(s.band||'—');
  document.getElementById('v-fw').textContent=s.fw||'—';
  document.getElementById('v-free').textContent=s.free||'—';
  document.getElementById('v-temp').textContent=(s.temp?s.temp+' °C':'—');
  document.getElementById('v-uptime').textContent=(s.uptime||0)+' мин';
  document.title=(s.playing?'▶ ':'')+'Станция Midi';
}

function refresh(){
  fetch('/api/status',{cache:'no-store'}).then(function(r){return r.json()}).then(paint).catch(function(){});
}
refresh();setInterval(refresh,5000);

vol.oninput=function(){volBusy=true;volLabel.textContent=vol.value+'%'};
vol.onchange=function(){
  fetch('/action?do=volume&v='+vol.value)
    .then(function(r){return r.text()}).then(function(t){
      if(t.indexOf('Громкость')<0)show(t);
      setTimeout(function(){volBusy=false},800);
    }).catch(function(e){show('ошибка: '+e);volBusy=false});
};

document.querySelectorAll('[data-a]').forEach(function(b){b.onclick=function(){
  if(b.dataset.a==='reboot'&&!confirm('Перезагрузить колонку?'))return;
  show('…');
  fetch('/action?do='+b.dataset.a)
    .then(function(r){return r.text()}).then(function(t){show(t);refresh()})
    .catch(function(e){show('ошибка: '+e)});
}});

document.querySelectorAll('[data-log]').forEach(function(b){b.onclick=function(){
  show('…');
  fetch('/log?name='+b.dataset.log).then(function(r){return r.text()}).then(show)
    .catch(function(e){show('ошибка: '+e)});
}});
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
