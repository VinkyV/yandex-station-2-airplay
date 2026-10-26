#!/bin/sh
# Сборка nqptp + shairport-sync с AirPlay 2 внутри alpine:3.24 (aarch64/musl)
set -e
mkdir -p /out/bin /out/lib /work/src
echo "=== deps ==="
apk add --no-cache build-base g++ autoconf automake libtool git pkgconf \
  alsa-lib-dev popt-dev libconfig-dev soxr-dev openssl-dev avahi-dev \
  ffmpeg-dev libplist-dev libplist-util libsodium-dev libgcrypt-dev util-linux-dev linux-headers \
  2>&1 | tail -5

echo "=== nqptp ==="
if [ -x /out/bin/nqptp ]; then
  echo "nqptp already built:"; /out/bin/nqptp -V || true
else
cd /work/src
[ -d nqptp ] || git clone --depth=1 -b 1.2.4 https://github.com/mikebrady/nqptp.git
cd nqptp
git log -1 --format='nqptp commit %h %s'
autoreconf -fi >/dev/null 2>&1
./configure >/dev/null
make -j4 2>&1 | tail -3
cp nqptp /out/bin/
./nqptp -V || true
fi

echo "=== shairport-sync 5.5.1 configure options ==="
cd /work/src
[ -d shairport-sync ] || git clone --depth=1 -b 5.5.1 https://github.com/mikebrady/shairport-sync.git
cd shairport-sync
autoreconf -fi >/dev/null 2>&1
./configure --help | grep -iE "airplay-2|ffmpeg|alsa|soxr|avahi|metadata|piddir" || true

echo "=== shairport-sync build ==="
./configure --sysconfdir=/etc --with-alsa --with-soxr --with-avahi \
  --with-ssl=openssl --with-airplay-2 --with-metadata --with-piddir=/run >/tmp/cfg.log 2>&1 || { tail -40 /tmp/cfg.log; exit 1; }
tail -25 /tmp/cfg.log
make -j4 2>&1 | tail -5
cp shairport-sync /out/bin/

echo "=== versions ==="
/out/bin/shairport-sync -V || true
echo "=== ldd shairport ==="
ldd /out/bin/shairport-sync
echo "=== ldd nqptp ==="
ldd /out/bin/nqptp
echo "=== sizes ==="
ls -l /out/bin/
