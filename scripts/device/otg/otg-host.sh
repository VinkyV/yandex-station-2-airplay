#!/bin/sh
# USB Host (OTG) на Яндекс.Станции Midi — порт Type-C из режима устройства в режим хоста.
# Платформа yandex,station-midi (amlogic, axg), ядро 4.9.68. Регистры PHY те же, что
# в рецепте для Станции Лайт; проверено на живом устройстве 24.10.2026.
#
# Что делает:
#   1) подгружает модули ядра (флешки, SD-картридеры, USB-Ethernet);
#   2) переключает порт: usb_r0.u2d_act=0, подтяжки 15 кОм, снимает SLEEPM0;
#   3) перепривязывает xhci-hcd и пересканирует накопители;
#   4) снимает флаг boot-pending только если хост реально поднялся.
#
# Откат без перезагрузки: otg-off.sh. Полное отключение: touch /data/otg/disable.
D=/data/otg
LOG=$D/last.log
MOD=$D/modules

mkdir -p "$D"
exec >>"$LOG" 2>&1
echo "=== $(date) ==="

if [ -f "$D/disable" ]; then
  echo "выключено флагом $D/disable"
  exit 0
fi

# Прошлая загрузка повисла после переключения — не повторяем, иначе бутлуп.
if [ -f "$D/boot-pending" ]; then
  echo "прошлая загрузка с OTG не завершилась — в этот раз режим хоста пропущен"
  rm -f "$D/boot-pending"
  exit 0
fi

# 1. Драйверы. Порядок важен: mii → usbnet → r8152, sd_mod → usb-storage → uas.
for m in mii usbnet r8152 sd_mod usb-storage uas; do
  [ -f "$MOD/$m.ko" ] || continue
  key=$(printf '%s' "$m" | tr '-' '_')
  grep -q "^$key " /proc/modules && { echo "модуль $m уже загружен"; continue; }
  if insmod "$MOD/$m.ko"; then echo "insmod $m ok"; else echo "insmod $m ОШИБКА"; fi
done

# 2. Переключение порта
if [ $(( $(devmem 0xffe09080 32) & 0x80000000 )) -eq 0 ]; then
  echo "порт уже в режиме хоста"
else
  touch "$D/boot-pending"
  echo ff400000.dwc2_a > /sys/bus/platform/drivers/dwc_otg/unbind 2>/dev/null
  echo xhci-hcd.0.auto > /sys/bus/platform/drivers/xhci-hcd/unbind 2>/dev/null
  sleep 1
  echo "до:    r0=$(devmem 0xffe09080 32) r4=$(devmem 0xffe09090 32) u2p=$(devmem 0xffe09020 32)"
  devmem 0xffe09084 32 $(( $(devmem 0xffe09084 32) & ~0x0000F000 ))   # u3h_host_u2_port_disable = 0
  devmem 0xffe09080 32 $(( $(devmem 0xffe09080 32) & ~0x80000000 ))   # u2d_act = 0: порт → xHCI
  devmem 0xffe09090 32 $(( $(devmem 0xffe09090 32) & ~0x00000002 ))   # p21_SLEEPM0 = 0
  devmem 0xffe09020 32 $(( $(devmem 0xffe09020 32) | 0x00000060 ))    # подтяжки 15 кОм (host)
  sleep 1
  echo "после: r0=$(devmem 0xffe09080 32) r4=$(devmem 0xffe09090 32) u2p=$(devmem 0xffe09020 32)"
  if echo xhci-hcd.0.auto > /sys/bus/platform/drivers/xhci-hcd/bind; then
    echo "xhci перепривязан"
  else
    echo "xhci не поднялся — откат"
    /data/otg/otg-off.sh
    exit 1
  fi
fi

# 3. Накопители: картридеры не сообщают о вставке карты, нужен пересчёт шины.
i=0
while [ $i -lt 6 ]; do
  # на раннем старте каталога может ещё не быть — без проверки glob подставляется
  # буквально и busybox ругается "nonexistent directory"
  set -- /sys/class/scsi_host/*
  if [ -d "$1" ]; then
    for h in "$@"; do echo 1 > "$h/scan" 2>/dev/null; done
  fi
  sleep 2
  i=$((i+1))
done

# 4. Флаг снимаем только при живом корневом хабе.
if [ -e /sys/bus/usb/devices/usb1/idVendor ]; then
  rm -f "$D/boot-pending"
  echo "готово: USB-host активен"
  for d in /sys/bus/usb/devices/1-*; do
    n=$(basename "$d")
    case "$n" in *:*) continue ;; esac
    echo "  $n $(cat "$d/idVendor" 2>/dev/null):$(cat "$d/idProduct" 2>/dev/null) $(cat "$d/product" 2>/dev/null)"
  done
else
  echo "корневой хаб не появился — оставляю флаг, следующий старт будет без OTG"
fi
