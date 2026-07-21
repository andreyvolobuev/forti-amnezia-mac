#!/bin/bash
# vpn-off.sh v2 — откат всего, что наставил vpn-on.sh (маршруты + /etc/hosts).
# Сами VPN-клиенты (Amnezia, Forti) отключай в их приложениях.
set -u

echo "=== VPN OFF v2 ==="

echo "[1/3] Убираю статические маршруты..."
for net in 91.221.198.0/24 91.221.199.0/24 \
  149.154.160.0/20 91.108.4.0/22 91.108.8.0/22 91.108.12.0/22 \
  91.108.16.0/22 91.108.20.0/22 91.108.56.0/22 95.161.64.0/20 91.105.192.0/23; do
  sudo route -n delete -net "$net" >/dev/null 2>&1 && echo "  del $net"
done

echo "[2/3] Убираю точечные маршруты и записи Claude из /etc/hosts..."
for ip in $(grep claude-direct /etc/hosts 2>/dev/null | awk '{print $1}'); do
  sudo route -n delete "$ip" >/dev/null 2>&1 && echo "  del $ip"
done
sudo sed -i '' '/claude-direct/d' /etc/hosts

echo "[3/3] Сбрасываю DNS-кэш..."
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null

echo "Готово. VPN-клиенты отключи вручную, если нужно."
