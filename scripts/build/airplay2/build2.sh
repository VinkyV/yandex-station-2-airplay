#!/bin/sh
# Минимальный статический ffmpeg (aac/alac) + пересборка shairport-sync с AirPlay 2
set -e
mkdir -p /out/bin /out/lib /work/ffout
echo "=== deps ==="
apk add --no-cache build-base g++ autoconf automake libtool git pkgconf \
  alsa-lib-dev popt-dev libconfig-dev soxr-dev openssl-dev avahi-dev \
  libplist-dev libplist-util libsodium-dev libgcrypt-dev util-linux-dev linux-headers \
  2>&1 | tail -3

if [ ! -f /work/ffout/lib/libavcodec.a ]; then
  echo "=== ffmpeg (minimal, static) build start $(date) ==="
  cd /work/src/ffmpeg
  [ -f config.h ] && make distclean >/dev/null 2>&1 || true
  ./configure --prefix=/work/ffout \
    --disable-everything --disable-programs --disable-doc --disable-network \
    --disable-avdevice --disable-avfilter --disable-swscale \
    --disable-autodetect --disable-shared --enable-static --enable-pic \
    --enable-decoder=aac,alac --enable-parser=aac \
    --enable-demuxer=mov --enable-protocol=file \
    >/tmp/ffcfg.log 2>&1 || { tail -30 /tmp/ffcfg.log; exit 1; }
  echo "configured $(date)"
  make -j4 >/tmp/ffmake.log 2>&1 || { tail -30 /tmp/ffmake.log; exit 1; }
  make install >/tmp/ffinst.log 2>&1
  echo "ffmpeg built $(date)"
fi
ls -l /work/ffout/lib/libav*.a /work/ffout/lib/libswresample.a

echo "=== shairport-sync relink (static ffmpeg) ==="
cd /work/src/shairport-sync
make distclean >/dev/null 2>&1 || true
export PKG_CONFIG_PATH=/work/ffout/lib/pkgconfig
./configure --sysconfdir=/etc --with-alsa --with-soxr --with-avahi \
  --with-ssl=openssl --with-airplay-2 --with-metadata --with-piddir=/run \
  >/tmp/cfg2.log 2>&1 || { tail -40 /tmp/cfg2.log; exit 1; }
grep -iE "airplay|avcodec|swresample" /tmp/cfg2.log | tail -6
make -j4 >/tmp/make2.log 2>&1 || { tail -40 /tmp/make2.log; exit 1; }
cp shairport-sync /out/bin/shairport-sync
strip /out/bin/shairport-sync 2>/dev/null || true
strip /out/bin/nqptp 2>/dev/null || true

echo "=== result ==="
/out/bin/shairport-sync -V
ls -l /out/bin/
echo "=== DT_NEEDED ==="
readelf -d /out/bin/shairport-sync | grep NEEDED
echo "=== closure ==="
for i in 1 2 3 4 5; do : > /tmp/c; for l in $(cat /tmp/b 2>/dev/null); do ldd "$l" 2>/dev/null | awk "/=>/ {print \$3}"; done >> /tmp/c; ldd /out/bin/shairport-sync 2>/dev/null | awk "/=>/ {print \$3}" >> /tmp/c; grep -v "^$" /tmp/c | sort -u > /tmp/b; done
echo "libs: $(wc -l < /tmp/b)"; du -cL $(cat /tmp/b) 2>/dev/null | tail -1
rm -rf /out/lib; mkdir -p /out/lib
for l in $(cat /tmp/b); do [ -f "$l" ] && cp -Lf "$l" /out/lib/; done
echo "copied: $(ls /out/lib | wc -l), size $(du -sh /out/lib | cut -f1)"
echo "=== AAC decoder check ==="
printf '#include <libavcodec/avcodec.h>\n#include <stdio.h>\nint main(){const AVCodec *a=avcodec_find_decoder(AV_CODEC_ID_AAC);const AVCodec *b=avcodec_find_decoder(AV_CODEC_ID_ALAC);printf("aac=%%s alac=%%s\\n",a?"OK":"MISSING",b?"OK":"MISSING");return 0;}\n' > /tmp/t.c
gcc /tmp/t.c -o /tmp/t $(pkg-config --cflags --libs libavcodec libavutil) && /tmp/t
echo "=== DONE $(date) ==="
