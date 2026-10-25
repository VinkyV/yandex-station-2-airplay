#!/bin/sh
# Сборка nqptp (отдельно, для CI). Зависимости уже поставлены build2.sh.
set -e
mkdir -p /out/bin /work/src
cd /work/src
[ -d nqptp ] || git clone --depth=1 https://github.com/mikebrady/nqptp.git
cd nqptp
git log -1 --format='nqptp commit %h %s'
autoreconf -fi >/dev/null 2>&1
./configure >/dev/null
make -j4 2>&1 | tail -3
cp nqptp /out/bin/nqptp
strip /out/bin/nqptp 2>/dev/null || true
/out/bin/nqptp -V || true
