#!/bin/sh
# Тест: гасим classic-приёмник и супервизор, поднимаем nqptp + AP2-приёмник
T2=/data/local/opt/airplay2
L=/data/local/opt/tools/lib/ld-musl-aarch64.so.1
S=/data/local/tmp/ap2-state.log
: > $S
say() { echo "$@" >> $S; }
say "=== $(date) ==="

[ -f /run/audio-owner.pid ] && kill "$(cat /run/audio-owner.pid)" 2>/dev/null
for p in $(ps w | awk '/[a]udio-owner\.sh/ {print $1}'); do kill "$p" 2>/dev/null; done
for p in $(ps w | awk '/[s]hairport-sync -c \/data\/local\/opt\/airplay\// {print $1}'); do kill "$p" 2>/dev/null; done
sleep 3
say "classic shairport after kill: $(ps w | grep -c '[s]hairport-sync -c /data/local/opt/airplay/')"
say "audio-owner after kill: $(ps w | grep -c '[a]udio-owner.sh')"

LD_LIBRARY_PATH=$T2/lib:/data/local/opt/tools/lib start-stop-daemon -S -b -m -p /run/nqptp.pid -x $L -- $T2/bin/nqptp
sleep 2
say "nqptp pid: $(cat /run/nqptp.pid 2>/dev/null) alive: $(ps w | grep -c '[n]qptp')"
say "--- udp 319/320:"
netstat -lnu 2>/dev/null | grep -E ":319|:320" >> $S
say "--- shm: $(ls -l /dev/shm 2>/dev/null | grep -c nqptp) entries in /dev/shm"

ADDR="$(cat /run/dbus/airplay.addr 2>/dev/null)"
say "bus: $ADDR"
: > /data/local/tmp/shairport2.log
start-stop-daemon -S -b -m -p /run/shairport2.pid -x /bin/sh -- $T2/bin/run-sps.sh
sleep 6
say "shairport2 pid: $(cat /run/shairport2.pid 2>/dev/null) alive: $(ps w | grep -c '[s]hairport-sync -c /data/local/opt/airplay2')"
say "--- tcp 5000:"
netstat -ln 2>/dev/null | grep ":5000" >> $S
say "--- log:"
tail -25 /data/local/tmp/shairport2.log >> $S
say "=== end ==="
