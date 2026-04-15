#!/bin/bash
echo "=== Enabling DNS pass-through rules ==="
sudo pfctl -ef ~/pf-dns-redirect.conf 2>&1 | grep -v "ALTQ"
echo ""
echo "Testing..."
curl -sI --connect-timeout 5 https://api.anthropic.com | head -1
curl -sI --connect-timeout 5 https://web.telegram.org | head -1
curl -sI --connect-timeout 5 https://youtube.com | head -1
echo "Done!"
