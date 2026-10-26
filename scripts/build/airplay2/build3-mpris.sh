#!/bin/sh
# Пересборка shairport-sync с D-Bus и MPRIS (для обратных команд AirPlay: пауза/дальше/назад)
# База — build2.sh; ffmpeg переиспользуется из /work/ffout.
set -e
mkdir -p /out/bin /out/lib /work/ffout
echo "=== deps ==="
apk add --no-cache build-base g++ autoconf automake libtool git pkgconf \
  alsa-lib-dev popt-dev libconfig-dev soxr-dev openssl-dev avahi-dev \
  libplist-dev libplist-util libsodium-dev libgcrypt-dev util-linux-dev linux-headers \
  dbus-dev dbus 2>&1 | tail -3

ls -l /work/ffout/lib/libav*.a

echo "=== shairport-sync configure (dbus + mpris) ==="
cd /work/src/shairport-sync
make distclean >/dev/null 2>&1 || true
[ -x ./configure ] || autoreconf -fi >/dev/null 2>&1
export PKG_CONFIG_PATH=/work/ffout/lib/pkgconfig
./configure --sysconfdir=/etc --with-alsa --with-soxr --with-avahi \
  --with-ssl=openssl --with-airplay-2 --with-metadata --with-piddir=/run \
  --with-dbus-interface --with-mpris-interface \
  >/tmp/cfg3.log 2>&1 || { tail -40 /tmp/cfg3.log; exit 1; }
grep -iE "dbus|mpris|airplay|avcodec" /tmp/cfg3.log | tail -10
make -j4 >/tmp/make3.log 2>&1 || { tail -40 /tmp/make3.log; exit 1; }
cp shairport-sync /out/bin/shairport-sync
strip /out/bin/shairport-sync 2>/dev/null || true

echo "=== result ==="
/out/bin/shairport-sync -V
for s in RemoteCommand playpause nextitem org.gnome.ShairportSync; do
  echo "  $s: $(strings /out/bin/shairport-sync | grep -c "$s")"
done
echo "=== closure ==="
for i in 1 2 3 4 5; do : > /tmp/c; for l in $(cat /tmp/b 2>/dev/null); do ldd "$l" 2>/dev/null | awk "/=>/ {print \$3}"; done >> /tmp/c; ldd /out/bin/shairport-sync 2>/dev/null | awk "/=>/ {print \$3}" >> /tmp/c; grep -v "^$" /tmp/c | sort -u > /tmp/b; done
echo "libs: $(wc -l < /tmp/b)"
rm -rf /out/lib; mkdir -p /out/lib
for l in $(cat /tmp/b); do [ -f "$l" ] && cp -Lf "$l" /out/lib/; done
ls /out/lib | grep -i dbus || echo "ВНИМАНИЕ: libdbus не попал в lib/"
echo "DONE $(date)"
