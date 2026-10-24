#!/bin/sh
# Возврат порта Type-C в режим устройства (как до включения OTG) без перезагрузки.
# Нужен, если что-то пошло не так: снимает модули и отдаёт порт gadget-контроллеру.
D=/data/otg
exec >>"$D/last.log" 2>&1
echo "=== $(date) откат ==="

echo xhci-hcd.0.auto > /sys/bus/platform/drivers/xhci-hcd/unbind 2>/dev/null
sleep 1
devmem 0xffe09020 32 $(( $(devmem 0xffe09020 32) & ~0x00000060 ))
devmem 0xffe09090 32 $(( $(devmem 0xffe09090 32) | 0x00000002 ))
devmem 0xffe09080 32 $(( $(devmem 0xffe09080 32) | 0x80000000 ))
sleep 1
if echo ff400000.dwc2_a > /sys/bus/platform/drivers/dwc_otg/bind 2>/dev/null; then
  echo "порт вернулся в режим устройства"
fi
for m in uas usb-storage sd_mod r8152 usbnet mii; do
  key=$(printf '%s' "$m" | tr '-' '_')
  if grep -q "^$key " /proc/modules; then rmmod "$key" 2>/dev/null && echo "rmmod $m"; fi
done
echo "готово"
