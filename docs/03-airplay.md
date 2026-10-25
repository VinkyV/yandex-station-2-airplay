# 03. AirPlay на колонке

Самая интересная часть: у Станции 2 нет AirPlay, а после root его можно добавить — колонка появится
на iPhone и Mac в списке AirPlay и будет играть в свои динамики.

Схема: `shairport-sync` + `avahi` для объявления в сети + маленький распорядитель,
который передаёт звуковое устройство между приёмником и штатным медиа-демоном.

> **AirPlay 2.** Ниже описана база (AirPlay 1), она нужна в любом случае — оттуда берутся
> `avahi`, `dbus`, `dropbear` и утилиты. Приёмник с AirPlay 2 собирается отдельно и поднимается
> поверх этой базы: см. [`07-airplay2-build.md`](07-airplay2-build.md). Там же — важное отличие:
> в AirPlay 2 порт случайный, и сессию надо ловить через `lsof`, а не по `netstat`.

```
                     ┌──────────────────────────────┐
  iPhone/Mac ───────▶│ shairport-sync :5000         │──┐
                     └──────────────────────────────┘  │   pcmC0D0p (ALSA)
                     ┌──────────────────────────────┐  ├──▶ динамики
  Алиса ────────────▶│ maind --mediad               │──┘
                     └──────────────────────────────┘
                        ↑ кто из них владеет устройством,
                          решает audio-owner.sh
```

## Что нужно

- root и SSH на колонке (см. `01-root.md`, `02-persistence.md`);
- набор musl-бинарников: `shairport-sync`, `avahi`, `dbus-daemon`, `dropbear`, `alsa-utils`
  (как собрать — `05-tools.md`);
- ничего компилировать на колонке не надо.

## Шаг 1. Своя шина D-Bus

Системная шина на Станции 2 — для служб Яндекса, и avahi в неё не пустят
(`not allowed to own the service "org.freedesktop.Avahi" due to security policies`).
Поднимаем отдельную шину:

`/data/local/etc/airplay-bus.conf`:

```xml
<busconfig>
  <type>system</type>
  <listen>unix:path=/run/dbus/airplay_bus</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow user="*"/>
    <allow own="*"/>
    <allow send_type="method_call"/>
    <allow send_type="signal"/>
    <allow send_requested_reply="true" send_type="method_return"/>
    <allow send_requested_reply="true" send_type="error"/>
    <allow receive_type="method_call"/>
    <allow receive_type="signal"/>
    <allow receive_type="method_return"/>
    <allow receive_type="error"/>
  </policy>
</busconfig>
```

```sh
L=/data/local/opt/tools/lib/ld-musl-aarch64.so.1
T=/data/local/opt/airplay
mkdir -p /run/dbus
"$L" "$T/bin/dbus-daemon" --config-file=/data/local/etc/airplay-bus.conf \
     --fork --print-address=1 > /run/dbus/airplay.addr
```

Адрес шины **обязательно** в `/run` (или другом месте, которое точно пишется при загрузке) и
читается оттуда всеми, кто стартует позже.

## Шаг 2. avahi с именем колонки

Главный подводный камень. У колонки уже работает mDNS: демон `maind` держит UDP 5353 и публикует
имя вида `yandex-station-gen2-<ID>.local`. Если avahi поднимется со своим именем, он получит
конфликт PTR/адресов, отзовёт записи и уйдёт переименовываться по кругу — телефон ничего не
увидит, хотя порт 5000 слушает.

**Решение:** дать avahi то же имя хоста, что у колонки.

`/data/local/opt/airplay/etc/avahi/avahi-daemon.conf`:

```ini
[server]
host-name=yandex-station-gen2-<ID>    # ровно как публикует maind
use-ipv4=yes
use-ipv6=no
ratelimit-interval-usec=1000000
ratelimit-burst=1000

[publish]
publish-hinfo=no
publish-workstation=no
```

Имя хоста колонки можно узнать так: `avahi-browse -at` или `dns-sd -B _raop._tcp` не покажет,
а вот mDNS-имя видно в приложении/сканере сети, либо в `ps w | grep maind` (аргументы),
либо `cat /etc/hostname`.

Пользователь `avahi` в системе отсутствует — добавляем (иначе avahi не стартует):

```sh
grep -q '^avahi:' /etc/passwd || echo 'avahi:x:86:86::/:/bin/false' >> /etc/passwd
grep -q '^avahi:' /etc/group  || echo 'avahi:x:86:' >> /etc/group
mkdir -p /run/avahi-daemon
```

Запуск — без сброса привилегий и без chroot (иначе падает на этой сборке):

```sh
DBUS_SYSTEM_BUS_ADDRESS="$(cat /run/dbus/airplay.addr)" \
LD_LIBRARY_PATH="$T/lib:/data/local/opt/tools/lib" \
  "$L" "$T/bin/avahi-daemon" --no-drop-root --no-chroot \
       -f "$T/etc/avahi/avahi-daemon.conf"
```

## Шаг 3. Звук

Штатный ALSA-конфиг (`/usr/share/alsa/alsa.conf`) тянет 32-битные плагины — musl-бинарник на нём
падает (`Exec format error`). Поэтому у приёмника свой конфиг:

`/data/local/etc/asound.conf`:

```
pcm.!default { type hw; card 0; device 0 }
ctl.!default { type hw; card 0 }
```

Устройство отдаём напрямую. Микшер (`dmix`) на этой сборке недоступен, поэтому «играть
одновременно с Алисой» не получится — нужен арбитраж (шаг 5).

## Шаг 4. Приёмник

`/data/local/opt/airplay/etc/shairport-sync.conf`:

```
general = {
    name = "Яндекс Станция";        // как будет в списке AirPlay
    service_type = "classic";      // AirPlay 1
    port = 5000;
    output_backend = "alsa";
    mdns_backend = "avahi";
    volume_range_db = 60;
    allow_session_interruption = "yes";
    session_timeout = 8;           // сколько держать сессию после тишины
};

alsa = {
    output_device = "default";
    audio_backend_buffer_desired_length_in_seconds = 0.5;
    disable_standby_mode = "auto"; // отпускать устройство в простое
};
```

Запуск:

```sh
LD_LIBRARY_PATH="$T/lib:/data/local/opt/tools/lib" \
ALSA_CONFIG_PATH=/data/local/etc/asound.conf \
DBUS_SYSTEM_BUS_ADDRESS="$(cat /run/dbus/airplay.addr)" \
  "$L" "$T/bin/shairport-sync" -c "$T/etc/shairport-sync.conf"
```

Проверка: `netstat -ln | grep 5000` и с телефона — устройство должно появиться в AirPlay.

## Шаг 5. Распорядитель звука

Проблема: `maind --mediad` открывает `pcmC0D0p` и держит его **постоянно** — даже когда ничего
не играет. Пока он жив, `shairport-sync` получает `EBUSY` и молчит: AirPlay «подключается»,
а звука нет.

Решение — `audio-owner.sh`: раз в несколько секунд смотрит, есть ли **установленное соединение
на порт приёмника** (7000 для AirPlay 2, 5000 для AirPlay 1).

* есть → освобождает устройство под приёмник (`maind --mediad` убивается);
* нет → поднимает `maind --mediad` обратно, Алиса снова говорит.

```sh
# Живая ли AirPlay-сессия (порт 7000 = 0x1B58, состояние 01 = ESTABLISHED)
airplay_session() {
  for t in /proc/net/tcp /proc/net/tcp6; do
    awk 'FNR>1 { split($2,a,":"); if (a[length(a)]=="1B58" && $4=="01") f=1 } END { exit(f?0:1) }' "$t" && return 0
  done
  return 1
}

# Одного kill мало: супервизор Quasar поднимает mediad обратно и тот снова хватает ALSA.
# Поэтому долбим, пока приёмник реально не займёт устройство.
release_for_airplay() {
  i=0
  while [ "$i" -lt 40 ]; do
    sp_holds_pcm && return 0
    airplay_session || return 0
    kill -9 $(pids_matching '/system/vendor/quasar/maind --mediad' | head -1) 2>/dev/null
    sleep 0.3; i=$((i+1))
  done
  return 1
}
```

**Ловушка, на которой мы потеряли вечер.** Нельзя определять «AirPlay играет» по признаку
«приёмник уже держит ALSA». Устройство держит `mediad`, приёмник его не получит никогда —
признак всегда ложный, скрипт ждёт приёмник, приёмник ждёт скрипт. Тишина, причём без единой
ошибки: в логе приёмника только `device is busy` / `no longer busy` по кругу. Признаком должна
быть **сессия (TCP)**, а не владение устройством.

**Порт этой сессии зависит от версии.** В 5.5 AirPlay 2 всегда слушал 7000 (`0x1B58`) и не смотрел
на `port` из конфига; в 5.6+ берётся то, что написано в `shairport-sync.conf` (у нас `5000`,
`0x1388`). Скрипты поэтому проверяют **оба** порта: иначе после обновления распорядитель, панель
и `airplay-ctl.sh` перестают видеть сессию, `mediad` держит звук, и в логе приёмника
`open_alsa_device: -16` / `Resource busy` — то есть ровно «AirPlay подключился, звука нет».

Две тонкости, без которых схема разваливается:

1. **Приёмник держит ALSA не только во время игры.** После сессии он продолжает занимать
   устройство — Алиса остаётся немой. Лечится перезапуском приёмника после сессии: он отпускает
   ALSA, но остаётся объявленным в сети.
2. **Лаунчер не поднимает `mediad` сразу** после падения (ждёт до 600 с), поэтому демон
   поднимает распорядитель сам, со своим окружением (`MALLOC_ARENA_MAX`, `CA_CERTIFICATES`).

Полный скрипт: [`scripts/device/audio-owner.sh`](../scripts/device/audio-owner.sh).

## Шаг 6. Управление AirPlay 2: пауза, дальше, назад

Обратного управления для AirPlay 2 официально нет. DACP (путь AirPlay 1) у нас не работает
и не заработает: источник не присылает `DACP-ID` в SETUP и не публикует `_dacp._tcp` —
проверено `dns-sd`, в сети не видно ни одной такой службы. Соответственно `send_simple_dacp_command()`
всегда упирается в «no port specified».

Рабочий механизм — другой: команда уходит plist-ом на **канал событий аудио-сессии**
(найдено в обсуждении shairport-sync [#2262](https://github.com/mikebrady/shairport-sync/discussions/2262)):

```
POST /command RTSP/1.0
Content-Type: application/x-apple-binary-plist

{ "type": "sendMediaRemoteCommand", "modernMediaRemoteCommand": <n> }
```

Номера как у Apple: `0` play, `1` pause, `2` toggle, `3` stop, `4` next, `5` previous.

Три вещи, без которых не работает:

1. **Именно аудио-соединение, не remote-control.** На канале `SETUP (RC)` тот же endpoint carries
   protobuf-сообщения MediaRemote; если писать туда plist, приёмника выбрасывает из сессии.
2. **Канал должен быть уже открыт.** `event_channel_fd > 0` — иначе отправлять некуда
   (проверяется в MPRIS-обработчике).
3. **Сборка с MPRIS.** В 5.5.x опции `--with-dbus` нет — есть `--with-dbus-interface` (спасибо
   Майку Брейди за уточнение). Мы собираем с `--with-mpris-interface`, потому что MPRIS — это и
   есть та ручка, которой мы командуем с колонки (`airplay-ctl.sh`, панель, голос); он тянет
   `libgio`/`libglib`. На колонку пришлось долить 10 библиотек, системные версии 32-битные и не
   подходят.

Что добавлено в исходники:

* `ap2_event_send_modern_media_remote_command()` — отправка plist-а на канал событий;
* реестр активного соединения в `rtsp.c` (`get_active_ap2_event_connection()`), заполняется
  в `ap2_event_receiver.c` при открытии канала;
* MPRIS-методы (`Next`, `Previous`, `PlayPause`, `Play`, `Pause`, `Stop`) сначала пробуют
  AP2-путь, иначе падают в DACP — для классического AirPlay поведение не изменилось.

**Грабли, на которых потеряли полчаса.** На нашей сборке (musl/Alpine dbus) `dbus-send` без
`--print-reply` отправляет вызов и сразу закрывает соединение — обработчик отменяется, и команда
молча пропадает (в логе ничего). С флагом работает. На Debian и Raspberry Pi OS такого, по словам
Майка Брейди, не наблюдается: это особенность нашей сборки, а не общее правило — но флаг поставить
не вредно в любом случае. Вторые грабли рядом: два экземпляра приёмника — звук держит один, а D-Bus-имя
занимает другой, и команды уходят в пустоту; поэтому запуск закрыт атомарной блокировкой (`mkdir`),
а поиск процесса идёт по `/proc`, не через `ps w` (busybox обрезает длинную командную строку с
musl-загрузчиком впереди).

Управление с колонки:

```sh
/data/local/bin/airplay-ctl.sh next|prev|pause|play|toggle|stop|status
```

Оно же навешено на панель (карточка «AirPlay») и на голос: если сессия активна, «дальше»/«назад»/
«пауза»/«продолжи» уходят источнику, а не нашему плееру.

**Проверено на живом Mac и на iPhone:** `next` переключает трек, `toggle` ставит на паузу и
снимает её. На iPhone работает так же — источник поддерживает команды 0–5, причём набор
разрешённых команд он сам присылает в `updateMRSupportedCommands` при подключении.

## Шаг 7. Автозапуск

При загрузке `S97station-root` стартует слишком рано: `/data` ещё не смонтирован, `/dev/snd` ещё
нет. Поэтому автозапуск AirPlay вынесен в `boot-airplay.sh`: он ждёт появления
`/data/local/opt/airplay/bin/shairport-sync` и `/dev/snd/pcmC0D0p`, потом поднимает шину, avahi,
приёмник и распорядителя.

```
/etc/init.d/S97station-root  →  boot-airplay.sh  →  dbus + avahi-keeper + shairport + audio-owner
```

Файлы: [`scripts/device/boot-airplay.sh`](../scripts/device/boot-airplay.sh),
[`scripts/device/avahi-keeper.sh`](../scripts/device/avahi-keeper.sh),
[`scripts/device/S97station-root.sh`](../scripts/device/S97station-root.sh).

## Проверка, что всё живо

```sh
ps w | grep -c '[a]vahi-daemon'       # 1
ps w | grep -c '[s]hairport-sync -c'  # 1
netstat -ln | grep -c ':5000'         # 1
netstat -tn | grep queue              # ждём ESTABLISHED при игре
```

С компьютера: `dns-sd -B _raop._tcp local` — в списке должна быть «Яндекс Станция».

## Грабли, на которые мы наступили

| Симптом | Причина | Лечение |
|---|---|---|
| Порт 5000 слушает, телефон не видит | shairport перезапущен с пустым адресом шины и ушёл на системную шину | адрес всегда из `/run/dbus/airplay.addr`; после перезагрузки `/run` пуст |
| Устройство то появляется, то нет | avahi с чужим именем хоста конфликтует с mDNS колонки | имя = имени колонки |
| AirPlay «подключён», звука нет | `maind --mediad` держит `pcmC0D0p` | распорядитель убивает демон при подключении |
| AirPlay «подключён», звука нет, в логе приёмника `busy`/`free` по кругу | признак «играет» считали по владению ALSA — а владеет ею `mediad`, круг замкнулся | признак = установленное соединение на 7000, устройство отдавать в цикле |
| После AirPlay Алиса молчит | приёмник не отпустил ALSA | перезапуск приёмника после сессии |
| Алиса молчит сразу после старта | `mediad` не поднят после падения | поднимать самому, с окружением |
| `aplay`/avahi падают с `Exec format error` | тянется 32-битный системный ALSA-конфиг | свой `ALSA_CONFIG_PATH` + `LD_LIBRARY_PATH` |
| avahi: `not allowed to own the service` | системная шина Яндекса | своя шина dbus |
| нет устройства `avahi` в `/etc/passwd` | avahi не может сбросить привилегии | добавить пользователя/группу |
| порт занят, приёмник не стартует | старый экземпляр `shairport-sync` | `kill -9` перед запуском |

## Почему только AirPlay 1

Для AirPlay 2 нужен `nqptp` (точная синхронизация времени) — в Alpine его нет. Поэтому нет
мультирума и сопряжения через «Дом». AirPlay 1 покрывает главное: играть звук с iPhone/Mac на
колонку.

## Если вы пришли из рецепта для Мини 3

На [hackalice.me](https://hackalice.me/recipes/airplay/) AirPlay ставят иначе — патчат штатный
`airplayd` в готовом пакете. Модель там другая (Мини 3), поэтому путь короче: ничего не надо
собирать. Построчное сравнение — что у нас устроено иначе и почему (своё управление, распорядитель
звука вместо хуков, конфликт mDNS, автозапуск): [`13-vs-airplay-recipe.md`](13-vs-airplay-recipe.md).
