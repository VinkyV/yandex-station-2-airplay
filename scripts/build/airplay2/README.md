# Сборка AirPlay 2 для Яндекс.Станции (aarch64, musl)

Скрипты, которыми собран приёмник AirPlay 2 на колонке. Запускаются в контейнере `alpine` под
нужную архитектуру, на маке ничего ставить не нужно.

## Порядок

```sh
# 1. Первый проход: nqptp + shairport-sync (без AirPlay 2 — проверка, что всё собирается)
docker run --rm --platform linux/arm64 \
  -v "$PWD:/work" -v "$PWD/out:/out" alpine:3.24 sh /work/build.sh

# 2. Второй проход: минимальный статический ffmpeg (aac/alac) и пересборка
#    shairport-sync уже с --with-airplay-2, плюс замыкание библиотек в out/lib
docker run --rm --platform linux/arm64 \
  -v "$PWD:/work" -v "$PWD/out:/out" alpine:3.24 sh /work/build2.sh
```

В дереве должны лежать исходники: `src/ffmpeg` (клон, нужная ветка) и `src/shairport-sync`
(тег 5.5.1). `nqptp` скрипт клонирует сам.

## Что получится

```
out/bin/shairport-sync   # с AirPlay 2, метаданными, ALSA, soxr, avahi
out/bin/nqptp            # демон точного времени (PTP, порты 319/320)
out/lib/                 # все зависимости, чтобы работало на колонке
```

Дальше на колонке — `/data/local/opt/airplay2/{bin,lib,etc}`, запуск через
`run-sps.sh` и `airplay2-daemon.sh` (см. `docs/07-airplay2-build.md` и `scripts/device/`).

## Файлы

| Файл | Что делает |
|---|---|
| `build.sh` | первый проход: зависимости Alpine, `nqptp`, `shairport-sync` |
| `build2.sh` | статический мини-ffmpeg (aac/alac) + пересборка с `--with-airplay-2`, сбор `out/lib` |
| `shairport-sync.conf` | конфиг приёмника: `service_type = "airplay2"`, порт 5000 (фактический RTSP — 7000) |
| `run-sps.sh` | запуск приёмника с musl-загрузчиком, своей шиной dbus и ALSA-конфигом |
| `test-ap2.sh` | проверка: гасит старую цепочку, поднимает `nqptp` + приёмник, пишет состояние в лог |

## Грабли

* `nqptp` обязателен и должен стартовать **до** приёмника, иначе AirPlay 2 не поднимется.
* Экземпляр `nqptp` должен быть один — дубли дерутся за 319/320.
* Порт RTSP в AirPlay 2 случайный (у нас 7000), поэтому «идёт ли воспроизведение» нельзя
  проверять по 5000 — только по `lsof` на pid приёмника.
