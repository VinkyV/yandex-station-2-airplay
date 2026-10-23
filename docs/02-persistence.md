# 02. Закрепление: SSH, автозапуск, заморозка обновлений

Короткое окно ADB — не то, на чём можно что-то строить. Дальше задача в том, чтобы доступ
восстанавливался сам при каждой загрузке, а прошивка не уезжала.

## Как включается отладка на Станции 2

`/system/vendor/quasar/onboot.sh` при старте вызывает `activate_adb.sh check`. Тот смотрит метки:

```
/data/quasar/activate_adb_quasmodrom
/data/quasar/activate_network_adb
```

Достаточно создать их — и отладка включается на каждой загрузке, без прокси и без облака.
`/system` на Станции 2 перемонтируется в rw, но править системные скрипты не нужно: метки лежат
в `/data`.

```sh
mount -o remount,rw /
mkdir -p /data/quasar
touch /data/quasar/activate_adb_quasmodrom /data/quasar/activate_network_adb
sync
```

## SSH вместо гонки за окном

`dropbear` из Alpine-набора, порт `2222`, вход только по ключу:

```sh
mkdir -p /data/local/etc/dropbear
dropbearkey -t ed25519 -f /data/local/etc/dropbear/host_ed25519
mkdir -p /data/local/.ssh && chmod 700 /data/local/.ssh
# публичный ключ с компьютера:
cat ~/.ssh/id_ed25519.pub >> /data/local/.ssh/authorized_keys
chmod 600 /data/local/.ssh/authorized_keys
```

Запуск (musl-бинарнику нужен свой загрузчик):

```sh
T=/data/local/opt/airplay
L=/data/local/opt/tools/lib/ld-musl-aarch64.so.1
LD_LIBRARY_PATH="$T/lib:/data/local/opt/tools/lib" \
  "$L" "$T/bin/dropbear" -r /data/local/etc/dropbear/host_ed25519 -p 2222 -P /run/dropbear.pid
```

> **Ловушка.** Домашний каталог `root` по `/etc/passwd` — `/root`, а не `/data/local`. Если
> `dropbear` запускается при загрузке (а не из adb-сессии, где `HOME=/data/local`), ключ он ищет
> в `/root/.ssh/authorized_keys`. Именно поэтому автозапуск кладёт копию ключа туда.

## Автозапуск

`/etc/init.d/S97station-root` (номер S97 — после монтирования `/data` и запуска системных служб):

```sh
mount -o remount,rw / 2>/dev/null
mkdir -p /data/quasar
touch /data/quasar/activate_adb_quasmodrom /data/quasar/activate_network_adb

# ключ там, где его ждёт dropbear
mkdir -p /root/.ssh
[ -f /data/local/.ssh/authorized_keys ] && \
  cp /data/local/.ssh/authorized_keys /root/.ssh/authorized_keys && \
  chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys

# ... dropbear, сторож обновлений, boot-airplay.sh — см. scripts/device/S97station-root.sh
```

Полный файл — [`scripts/device/S97station-root.sh`](../scripts/device/S97station-root.sh).

### Почему `start-stop-daemon` с `-p`

`start-stop-daemon -x /bin/sh` считает процесс запущенным, если **уже есть любой** `/bin/sh`
— то есть всегда. Рабочий вариант:

```sh
start-stop-daemon -S -b -m -p /run/audio-owner.pid -x /bin/sh -- /data/local/bin/audio-owner.sh
```

## Заморозка обновлений

Обновлением занимается задача `updatesd` в `/system/vendor/quasar/launch.json`. Убираем её из
списка задач и ставим сторожа, который возвращает удаление, если облако попробует включить
её обратно (`scripts/device/watch-launchd.sh`).

Проверка:

```sh
grep -c updatesd /system/vendor/quasar/launch.json     # 0
ps w | grep -c '[u]pdatesd'                            # 0
tail -5 /data/local/tmp/watch-launchd.log
```

Сторож пишет в лог каждое срабатывание — по нему видно, пыталось ли облако вернуть обновление.

## Жёсткая блокировка OTA (второй слой)

Убрать `updatesd` из `launch.json` — это запрет **демону** обновлений. Но сам применитель
`/system/vendor/quasar/device_ota_update.sh` остаётся рабочим: если образ OTA как-то попадёт на
устройство, он распакует его и прошьёт.

Полный набор — [`scripts/device/ota-block.sh`](../scripts/device/ota-block.sh):

1. оригинал сохраняется (`device_ota_update.sh.orig` и копия в `/data/local/backup`);
2. вместо него ставится обёртка: пишет в `/data/local/tmp/ota-blocked.log` и отказывает;
3. **обход**: если существует `/data/local/allow_ota`, обёртка выполняет оригинал — то есть
   штатное обновление остаётся возможным по явному разрешению;
4. маркеры ADB делаются неизменяемыми: `chattr +i /data/quasar/activate_*` (проверка —
   `lsattr`, удаление отвечает `Operation not permitted`).

Подмена `ota_script.pub` на «чужой» ключ (как делают некоторые наборы) **не рекомендуется**:
это единственная правка, которую нельзя отменить на месте, если понадобится восстановление.

Проверка блока:

```sh
sh /system/vendor/quasar/device_ota_update.sh /tmp/fake.ota   # откажет, код 1
tail -3 /data/local/tmp/ota-blocked.log
```

## Бэкап перед правками

```sh
cp /system/vendor/quasar/launch.json /data/local/backup/launch.json.orig
cp /system/vendor/quasar/onboot.sh   /data/local/backup/onboot.sh.orig
```

Всё, что меняется, лежит в `/data` — её полный сброс стирает; `/system` переживает сброс, если
не приезжает новая прошивка.
