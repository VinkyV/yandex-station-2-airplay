# 07. Сборка AirPlay 2 (shairport-sync + nqptp)

Возвращаясь к вопросу из `03-airplay.md`: AirPlay 1 работает «из коробки» на пакете Alpine,
а для **AirPlay 2** нужны две вещи, которых в Alpine нет, — сам приёмник, собранный с
`--with-airplay-2`, и демон точного времени `nqptp`. Оба собираются в контейнере под aarch64/musl.

## Зачем контейнер

Собирать на маке под чужую архитектуру — это отдельный тулчейн и часы возни. Проще запустить
`alpine` под нужную архитектуру: там уже есть и musl, и apk, и нужные `-dev` пакеты.

```sh
docker run --rm --platform linux/arm64 \
  -v "$PWD:/work" -v "$PWD/out:/out" alpine:3.24 sh /work/build2.sh
```

## Что делает сборка

1. `apk add` — build-base, autoconf/automake, alsa-lib-dev, popt-dev, libconfig-dev, soxr-dev,
   openssl-dev, avahi-dev, libplist-dev, libsodium-dev, libgcrypt-dev.
2. **Минимальный статический ffmpeg.** AirPlay 2 приносит звук в AAC и ALAC, и shairport нужен
   декодер. Полный ffmpeg — десятки мегабайт, поэтому собираем только нужное:

```sh
./configure --prefix=/work/ffout \
  --disable-everything --disable-programs --disable-doc --disable-network \
  --disable-avdevice --disable-avfilter --disable-swscale \
  --disable-autodetect --disable-shared --enable-static --enable-pic \
  --enable-decoder=aac,alac --enable-parser=aac \
  --enable-demuxer=mov --enable-protocol=file
```

3. **nqptp** — из исходников, без зависимостей:

```sh
git clone --depth=1 https://github.com/mikebrady/nqptp.git
autoreconf -fi && ./configure && make
```

4. **shairport-sync 5.5.1 с AirPlay 2:**

```sh
./configure --sysconfdir=/etc --with-alsa --with-soxr --with-avahi \
  --with-ssl=openssl --with-airplay-2 --with-metadata --with-piddir=/run
make -j4
```

5. **Замыкание библиотек.** Собираем все `DT_NEEDED` рекурсивно и копируем в `out/lib`,
   чтобы бинарники запускались на колонке через musl-загрузчик без системных библиотек.

Результат: `shairport-sync` (с AirPlay 2) и `nqptp`, плюс каталог `lib/`.

## Установка на колонку

```
/data/local/opt/airplay2/
  bin/  shairport-sync, nqptp
  lib/  все зависимости
  etc/  shairport-sync.conf   (service_type = "airplay2")
```

Запуск приёмника (`run-sps.sh`):

```sh
export LD_LIBRARY_PATH=$T2/lib:/data/local/opt/tools/lib
export ALSA_CONFIG_PATH=/data/local/etc/asound.conf
export DBUS_SYSTEM_BUS_ADDRESS="$(cat /run/dbus/airplay.addr)"
exec $L $T2/bin/shairport-sync -c $T2/etc/shairport-sync.conf
```

`airplay2-daemon.sh` поднимает по порядку: шину dbus → avahi → **nqptp** → приёмник.
`nqptp` обязан стартовать раньше приёмника, иначе AirPlay 2 не поднимется.

## Главное отличие от AirPlay 1: порт

В AirPlay 1 приёмник слушает `5000`, и сессию легко ловить по `netstat`. В AirPlay 2 порт
**случайный** (у нас — `7000`), а соединение живёт на нём же. Поэтому распорядитель звука
определяет «идёт ли воспроизведение» через `lsof` по pid приёмника:

```sh
playing() {
  P=$(sp_pid)                       # pid shairport-sync из /data/local/opt/airplay2
  [ -z "$P" ] && return 1
  lsof -nP -a -p "$P" -i TCP -s TCP:ESTABLISHED | grep -q ESTABLISHED
}
```

Проверка по фиксированному порту 5000 в этой схеме **не работает** — сессия будет считаться
законченной, и распорядитель начнёт войну за звуковое устройство.

## Грабли

| Симптом | Причина | Лечение |
|---|---|---|
| Приёмник стартует, но невидим и молчит | нет `nqptp` или он поднят после приёмника | `nqptp` первым, `service_type = "airplay2"` |
| AirPlay «играет», Алиса не возвращается | распорядитель смотрит на порт 5000 | ловить сессию через `lsof` по pid |
| Звук пропадает при подключении | `maind --mediad` держит ALSA | тот же распорядитель, что и для AirPlay 1 |
| Колонка очень громкая после экспериментов | каналы усилителя выкручены в 255 | вернуть штатные: мастер 214, каналы 159 |
| Тихо даже на 100% | в конфиге `volume_range_db`, а громкость занижена в ALSA | регулировать только мастер усилителя |

## Совместимость с AirPlay 1

Старый набор (`/data/local/opt/airplay`, `service_type = "classic"`, порт 5000) никуда не
девается — он же даёт `dropbear`, `avahi`, `dbus` и утилиты. То есть AirPlay 2 — это
надстройка, а не замена: база по-прежнему нужна.
