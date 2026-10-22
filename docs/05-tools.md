# 05. Сборка musl-набора утилит

На колонке нет пакетного менеджера, нет компилятора, а прикладной слой 32-битный. Единственный
разумный путь — взять готовые бинарники из Alpine (aarch64, musl) и собрать из них автономный
набор, который живёт в `/data/local` и ничего не требует от системы.

## Почему именно так

| Вариант | Почему не подошёл |
|---|---|
| Сборка на самой колонке | нет компилятора и места под тулчейн |
| Кросс-компиляция под bionic/glibc | прикладной слой 32-битный, ядро 64-битное — легко попасть в несовместимость |
| Готовые статические бинарники «из интернета» | непроверяемые, от незнакомых авторов |
| **Пакеты Alpine + свой musl-загрузчик** | подписи проверяемы, зависимости замыкаются внутри набора |

## Проверка пакетов

1. Индекс (`APKINDEX.tar.gz`) подписан ключом Alpine — проверяем `openssl dgst -sha1 -verify`.
2. У каждого пакета в индексе есть поле `C:` — sha256 файла; сверяем.
3. Собственная подпись `.apk` покрывает **control-сегмент**: в конце файла лежит
   `.SIGN.RSA.…`, а перед ним — `Q1` = sha1 сжатого control-сегмента (gzip, нулевые размер/timestamp).
   Считаем Q1 сами и проверяем RSA-подписью тем же ключом Alpine.
4. Все файлы готового набора перечислены в `MANIFEST.txt` с sha256.

Скрипты: [`scripts/build/build_toolset.py`](../scripts/build/build_toolset.py),
[`scripts/build/pack.py`](../scripts/build/pack.py).

## Что входит

**Базовый набор** (`tools-aarch64-musl.tar.gz`, ~51 пакет): `jq`, `strace`, `lsof`, `tmux`, `rsync`,
`dig`/`host`/`nslookup`, `nc`, `socat`, `unzip`, `zstd`, `pv`, `less`, `tree`, `file` + `lib/` со
всеми `.so` + `ld-musl-aarch64.so.1` + `share/terminfo`.

**AirPlay-набор** (`airplay-aarch64-musl.tar.gz`, ~49 пакетов, ~13 МБ): `shairport-sync 5.5.1`,
`avahi`, `dbus`, `mpg123`, `alsa-utils`, `dropbear`, `curl`, `ca-certificates` и зависимости.

`nqptp` (нужен для AirPlay 2) в Alpine отсутствует — поэтому приёмник только AirPlay 1.

## Установка на колонку

Busybox `tar` не умеет `-z`:

```sh
gzip -dc tools-aarch64-musl.tar.gz | tar -xf - -C /data/local/opt/tools
gzip -dc airplay-aarch64-musl.tar.gz | tar -xf - -C /data/local/opt/airplay
```

Запуск любого бинарника:

```sh
L=/data/local/opt/tools/lib/ld-musl-aarch64.so.1
LD_LIBRARY_PATH=/data/local/opt/airplay/lib:/data/local/opt/tools/lib \
  "$L" /data/local/opt/airplay/bin/shairport-sync --help
```

Обёртки в `/data/local/bin` (чтобы не писать загрузчик каждый раз):

```sh
#!/bin/sh
exec /data/local/opt/tools/lib/ld-musl-aarch64.so.1 \
     --library-path /data/local/opt/tools/lib /data/local/opt/tools/bin/jq "$@"
```

## Подводные камни

- `LD_LIBRARY_PATH` глобально лучше не выставлять: системные 32-битные программы Яндекса
  подхватят 64-битные библиотеки и упадут. Передавайте окружение только своим бинарникам.
- Системный `/usr/share/alsa/alsa.conf` тянет 32-битные плагины — для musl-программ задавайте
  свой `ALSA_CONFIG_PATH` (см. `03-airplay.md`).
- `tar` из busybox не понимает `-z`, `cp -a` работает, но `cp --reflink` — нет.
