#!/bin/bash
# vpn-on.sh v2 — Amnezia (AmneziaWG) + FortiClient EMS одновременно.
# Порядок: 1) подключи Amnezia  2) запусти скрипт  3) жми Connect в Forti по подсказкам (MFA-пуш).
# Схема и диагноз: см. README-vpn.md
set -u

FORTI_SVC=$(scutil --nc list | grep -i forticlient | grep -oE '[0-9A-F-]{36}' | head -1)
GW=$(route -n get -ifscope en0 default 2>/dev/null | awk '/gateway/{print $2}')
GW=${GW:-192.168.1.1}

awg_if() { ifconfig | grep -B1 "inet 10\.8\." | grep "^utun" | cut -d: -f1 | head -1; }

check_gitlab() {
  local c
  c=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 4 https://gitlab.2gis.ru/)
  [ "$c" = "302" ] || [ "$c" = "200" ]
}

echo "=== VPN ON v2: Amnezia + Forti ==="

# --- 0. Amnezia должна быть подключена ---
AWG_IF=$(awg_if)
if [ -z "$AWG_IF" ]; then
  echo "Amnezia не подключена (нет интерфейса 10.8.x). Подключи её и запусти скрипт снова."
  exit 1
fi
if [ -z "$FORTI_SVC" ]; then
  echo "Не нашёл Forti-подключение в scutil --nc list. Проверь, установлен ли FortiClient."
  exit 1
fi
echo "Amnezia: $AWG_IF | шлюз en0: $GW | Forti svc: $FORTI_SVC"

# --- 1. Вывести шлюзы 2GIS из-под Amnezia (иначе туннель Forti рвётся сразу после коннекта) ---
echo ""
echo "[1/4] Обходные маршруты для шлюзов 2GIS (91.221.198/23 -> en0)..."
for net in 91.221.198.0/24 91.221.199.0/24; do
  sudo route -n delete -net "$net" >/dev/null 2>&1
  sudo route -n add -net "$net" "$GW" >/dev/null 2>&1 && echo "  $net -> $GW"
done

# --- 2. Forti: подключение + реролл до рабочей сессии gitlab ---
echo ""
echo "[2/4] Жми Connect в FortiClient (подтверждай MFA-пуш). Слежу за статусом..."
ATTEMPT=0
while true; do
  while [ "$(scutil --nc status "$FORTI_SVC" | head -1)" != "Connected" ]; do sleep 1; done
  ATTEMPT=$((ATTEMPT+1))
  sleep 2   # даём маршрутам Forti устаканиться
  if check_gitlab; then
    sleep 3
    if check_gitlab; then break; fi   # двойная проверка от ложных срабатываний
  fi
  echo "  x попытка #$ATTEMPT: плохая сессия (gitlab закрыт). Отключаю — жми Connect снова."
  afplay /System/Library/Sounds/Basso.aiff 2>/dev/null
  scutil --nc stop "$FORTI_SVC"
  while [ "$(scutil --nc status "$FORTI_SVC" | head -1)" = "Connected" ]; do sleep 1; done
done
echo "  OK попытка #$ATTEMPT: сессия рабочая, gitlab открыт."
afplay /System/Library/Sounds/Glass.aiff 2>/dev/null

# --- 3. Вернуть Telegram и Claude в Amnezia (Forti их перехватывает) ---
echo ""
echo "[3/4] Telegram-подсети и Claude -> Amnezia..."
AWG_IF=$(awg_if)   # интерфейс мог смениться
for subnet in 149.154.160.0/20 91.108.4.0/22 91.108.8.0/22 91.108.12.0/22 \
  91.108.16.0/22 91.108.20.0/22 91.108.56.0/22 95.161.64.0/20 91.105.192.0/23; do
  sudo route -n delete -net "$subnet" >/dev/null 2>&1
  sudo route -n add -net "$subnet" -interface "$AWG_IF" >/dev/null 2>&1
done
echo "  telegram-подсети -> $AWG_IF"

API_IP=$(dig @1.1.1.1 api.anthropic.com +short +timeout=3 | grep -E '^[0-9.]+$' | head -1)
WEB_IP=$(dig @1.1.1.1 claude.ai +short +timeout=3 | grep -E '^[0-9.]+$' | head -1)
case "$API_IP" in
  10.*|"") echo "  ПРОПУСК hosts: Amnezia не ответила на DNS, /etc/hosts не трогаю" ;;
  *)
    sudo sed -i '' '/claude-direct/d' /etc/hosts
    # защита от склейки: файл обязан заканчиваться переводом строки, иначе tee -a приклеит запись к последней строке
    [ -n "$(tail -c1 /etc/hosts)" ] && echo | sudo tee -a /etc/hosts >/dev/null
    printf '%s api.anthropic.com # claude-direct\n' "$API_IP" | sudo tee -a /etc/hosts >/dev/null
    printf '%s claude.ai # claude-direct\n' "${WEB_IP:-$API_IP}" | sudo tee -a /etc/hosts >/dev/null
    sudo route -n add "$API_IP" -interface "$AWG_IF" >/dev/null 2>&1
    [ -n "$WEB_IP" ] && sudo route -n add "$WEB_IP" -interface "$AWG_IF" >/dev/null 2>&1
    echo "  Claude -> $API_IP (hosts + route)"
    ;;
esac
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null

# --- 4. Контроль ---
echo ""
echo "[4/4] Проверка:"
printf "  %-9s " "gitlab:";   curl -s -o /dev/null -w "http %{http_code}\n" --connect-timeout 5 https://gitlab.2gis.ru/
printf "  %-9s " "planeta:";  curl -s -o /dev/null -w "http %{http_code}\n" --connect-timeout 5 https://planeta.2gis.ru/
printf "  %-9s " "claude:";   curl -4 -s -o /dev/null -w "http %{http_code}\n" --connect-timeout 8 https://api.anthropic.com/
printf "  %-9s " "telegram:"; curl -s -o /dev/null -w "http %{http_code}\n" --connect-timeout 8 https://web.telegram.org/
printf "  %-9s " "internet:"; curl -s -o /dev/null -w "http %{http_code}\n" --connect-timeout 5 https://ya.ru/
echo ""
echo "Готово. Перезапусти Claude Desktop (Cmd+Q), если был открыт."
