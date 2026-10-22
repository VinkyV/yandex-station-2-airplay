# 04. Откат

Что именно меняется на колонке и как вернуть штатное состояние.

## Что мы меняем

| Где | Что | Переживает полный сброс |
|---|---|---|
| `/data/quasar/activate_*` | метки активации ADB | нет |
| `/data/local/opt/*`, `/data/local/bin/*` | утилиты, приёмник, скрипты | нет |
| `/data/local/.ssh`, `/data/local/etc/dropbear` | ключи SSH | нет |
| `/root/.ssh/authorized_keys` | копия ключа для dropbear | да (до смены прошивки) |
| `/etc/passwd`, `/etc/group` | пользователь `avahi` | да |
| `/etc/init.d/S97station-root` | автозапуск | да |
| `/system/vendor/quasar/launch.json` | без задачи `updatesd` | да, если прошивка не менялась |
| Роутер | три статических DNS-записи | — |

## Мягкий откат (оставить root, убрать AirPlay)

```sh
for p in $(ps w | awk '/[s]hairport-sync/ {print $1}'); do kill "$p"; done
for p in $(ps w | awk '/audio-owner\.sh/ {print $1}'); do kill "$p"; done
for p in $(ps w | awk '/[a]vahi-daemon/ {print $1}'); do kill "$p"; done
rm -f /etc/init.d/S97station-root     # или убрать из него строку boot-airplay.sh
```

Медиа-демон вернётся сам (или поднимите вручную):

```sh
cd /data/quasar
MALLOC_ARENA_MAX=2 CA_CERTIFICATES=/system/vendor/quasar/ca-certificates.crt \
  nohup /system/vendor/quasar/maind --mediad >> /data/quasar/mediad.log 2>&1 &
```

## Полный откат (вернуть штатную колонку)

1. Убрать статические DNS-записи на роутере:

```
no ip host quasar.yandex.net
no ip host quasar.yandex.ru
no ip host scbh.yandex.net
system configuration save
```

2. Вернуть `launch.json` из бэкапа:

```sh
cp /data/local/backup/launch.json.orig /system/vendor/quasar/launch.json
```

3. Удалить автозапуск и метки:

```sh
rm -f /etc/init.d/S97station-root
rm -rf /data/local/opt/airplay /data/local/opt/tools
rm -f /data/local/bin/*.sh
rm -rf /data/local/etc/dropbear /data/local/.ssh /root/.ssh
rm -f /data/quasar/activate_adb_quasmodrom /data/quasar/activate_network_adb
```

4. Полный сброс колонки (кнопка выключения микрофонов при подаче питания, отпустить на жёлтом
   свете). После него прошивка — заводская, `/data` стёрта, root-доступа нет.

## Что важно не сделать

- **Не делайте полный сброс до того, как убедитесь, что он вам действительно нужен.** Вместе с
  `/data` уходят метки, утилиты и ключи — весь доступ придётся добывать заново.
- Не добавляйте утёкший CA в доверенные на компьютере: он скомпрометирован публично.
- Не оставляйте сетевой ADB (`5555`) включённым в недоверенной сети — он без аутентификации.
