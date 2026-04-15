#!/bin/bash
echo "=== Activating DNS redirect ==="
sudo brew services start dnsmasq 2>/dev/null
sudo pfctl -ef ~/pf-dns-redirect.conf 2>&1
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null
echo ""
echo "Testing dnsmasq (direct)..."
dig @127.0.0.1 -p 5354 api.anthropic.com +short
dig @127.0.0.1 -p 5354 sslvpn.2gis.one +short
echo ""
echo "Testing system DNS (via pf redirect)..."
nslookup api.anthropic.com 2>&1 | tail -3
nslookup youtube.com 2>&1 | tail -3
echo ""
echo "Testing HTTP..."
curl -sI --connect-timeout 5 https://api.anthropic.com | head -2
curl -sI --connect-timeout 5 https://web.telegram.org | head -2
curl -sI --connect-timeout 5 https://youtube.com | head -2
echo "Done!"
