#!/bin/bash
sudo pfctl -d 2>&1
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null
echo "pf disabled, DNS back to normal"
