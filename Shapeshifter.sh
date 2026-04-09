#!/bin/bash
# Simple WiFi anonymizer: disconnect, spoof MAC, change hostname, reconnect
# Press any key to restore and exit

echo ""
echo "░█▀▀░█░█░█▀█░█▀█░█▀▀░█▀▀░█░█░▀█▀░█▀▀░▀█▀░█▀▀░█▀▄"
echo "░▀▀█░█▀█░█▀█░█▀▀░█▀▀░▀▀█░█▀█░░█░░█▀▀░░█░░█▀▀░█▀▄"
echo "░▀▀▀░▀░▀░▀░▀░▀░░░▀▀▀░▀▀▀░▀░▀░▀▀▀░▀░░░░▀░░▀▀▀░▀░▀"
echo ""

set -euo pipefail

# Root check
if [ "$EUID" -ne 0 ]; then
  echo "Run as root" >&2
  exit 1
fi

# Auto-detect WiFi interface
IFACE=$(for i in /sys/class/net/*; do [ -d "$i/wireless" ] && echo "${i##*/}" && break; done)

if [ -z "$IFACE" ]; then
  echo "No wireless interface found" >&2
  exit 1
fi

# Configuration
NEW_MAC="$(printf '00:%02X:%02X:%02X:%02X:%02X' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)))"
NEW_HOSTNAME="anon-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' ')"

# Save old MAC and hostname
OLD_MAC_FILE="/tmp/old_mac_${IFACE}"
OLD_HOSTNAME_FILE="/tmp/old_hostname"
ip link show "$IFACE" | awk '/link\/ether/ {print $2}' >"$OLD_MAC_FILE" || true
hostname >"$OLD_HOSTNAME_FILE" || true

OLD_MAC=$(cat "$OLD_MAC_FILE")
OLD_HOSTNAME=$(cat "$OLD_HOSTNAME_FILE")

echo "Interface: $IFACE"
echo "Old MAC: $OLD_MAC"
echo "Old hostname: $OLD_HOSTNAME"
echo ""

# Cleanup function - restores original state
cleanup() {
  echo ""
  echo "[*] Restoring original MAC and hostname..."

  ip link set dev "$IFACE" down
  ip link set dev "$IFACE" address "$OLD_MAC"
  ip link set dev "$IFACE" up

  if command -v hostnamectl &>/dev/null; then
    hostnamectl set-hostname "$OLD_HOSTNAME"
  else
    echo "$OLD_HOSTNAME" >/etc/hostname
    hostname "$OLD_HOSTNAME"
  fi

  dhclient -r "$IFACE" 2>/dev/null || true
  sleep 2
  dhclient "$IFACE" 2>/dev/null || true

  echo "✓ Restored!"
  echo "MAC: $OLD_MAC"
  echo "Hostname: $OLD_HOSTNAME"
  echo ""
}

# Run cleanup on exit
trap cleanup EXIT

# Step 1: Disconnect WiFi
echo "[*] Disconnecting WiFi..."
ip link set dev "$IFACE" down

# Step 2: Change MAC address
echo "[*] Changing MAC address to $NEW_MAC..."
ip link set dev "$IFACE" address "$NEW_MAC"

# Step 3: Change hostname
echo "[*] Changing hostname to $NEW_HOSTNAME..."
if command -v hostnamectl &>/dev/null; then
  hostnamectl set-hostname "$NEW_HOSTNAME"
else
  echo "$NEW_HOSTNAME" >/etc/hostname
  hostname "$NEW_HOSTNAME"
fi

# Step 4: Turn WiFi back on
echo "[*] Reconnecting WiFi..."
ip link set dev "$IFACE" up

# Refresh DHCP
dhclient -r "$IFACE" 2>/dev/null || true
sleep 2
dhclient "$IFACE" 2>/dev/null || true

echo ""
echo "✓ Done!"
echo "New MAC: $NEW_MAC"
echo "New hostname: $NEW_HOSTNAME"
echo ""
echo "Press any key to restore and exit..."
echo ""

# Wait for user keypress
read -r -s -n 1

exit 0
