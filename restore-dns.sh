#!/bin/bash
echo "=== Disabling pf rules ==="
sudo pfctl -d 2>&1 | grep -v "ALTQ"
echo "Done"
