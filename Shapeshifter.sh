#!/bin/bash
# WiFi anonymizer using macchanger
# Spoofs MAC address and hostname, restores on exit
# Press any key to restore and exit

clear

echo ""
echo "░█▀▀░█░█░█▀█░█▀█░█▀▀░█▀▀░█░█░▀█▀░█▀▀░▀█▀░█▀▀░█▀▄"
echo "░▀▀█░█▀█░█▀█░█▀▀░█▀▀░▀▀█░█▀█░░█░░█▀▀░░█░░█▀▀░█▀▄"
echo "░▀▀▀░▀░▀░▀░▀░▀░░░▀▀▀░▀▀▀░▀░▀░▀▀▀░▀░░░░▀░░▀▀▀░▀░▀"
echo ""

set -euo pipefail

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
RESET='\033[0m'

# Root check
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Shapeshifter must be run as root${RESET}" >&2
  exit 1
fi

# Check if macchanger is installed
if ! command -v macchanger &>/dev/null; then
  echo -e "${RED}macchanger not installed${RESET}" >&2
  exit 1
fi

# Auto-detect WiFi interface
IFACE=$(for i in /sys/class/net/*; do [ -d "$i/wireless" ] && echo "${i##*/}" && break; done)

if [ -z "$IFACE" ]; then
  echo "${RED}No wireless interface found${RESET}" >&2
  exit 1
fi

# Generate new hostname
NEW_HOSTNAME="anon-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' ')"

# Save original hostname
OLD_HOSTNAME_FILE="/tmp/old_hostname"
hostname >"$OLD_HOSTNAME_FILE" || true
OLD_HOSTNAME=$(cat "$OLD_HOSTNAME_FILE")

echo "Interface: $IFACE"
echo "Old hostname: $OLD_HOSTNAME"
echo ""

# Cleanup function - restores original state
cleanup() {
  echo ""
  echo "[*] Restoring original MAC and hostname..."

  # Disconnect before restoring MAC
  ip link set dev "$IFACE" down 2>/dev/null || true
  sleep 1

  # Restore MAC
  macchanger -p "$IFACE" >/dev/null 2>&1 || true

  # Restore hostname
  if command -v hostnamectl &>/dev/null; then
    hostnamectl set-hostname "$OLD_HOSTNAME"
  else
    echo "$OLD_HOSTNAME" >/etc/hostname
    hostname "$OLD_HOSTNAME"
  fi

  # Reconnect
  ip link set dev "$IFACE" up 2>/dev/null || true
  sleep 2

  # Refresh DHCP
  dhclient -r "$IFACE" 2>/dev/null || true
  sleep 2
  dhclient "$IFACE" 2>/dev/null || true

  echo -e "${GREEN}✓ Restored!${RESET}"
  echo "Hostname: $OLD_HOSTNAME"
  echo ""
}

# Run cleanup on exit
trap cleanup EXIT

# Step 1: Disconnect WiFi
echo "[*] Disconnecting WiFi..."
ip link set dev "$IFACE" down
sleep 1

# Step 2: Change MAC address
echo "[*] Changing MAC address (random)..."
macchanger -r "$IFACE"

# Step 3: Change hostname
echo "[*] Changing hostname to $NEW_HOSTNAME..."
if command -v hostnamectl &>/dev/null; then
  hostnamectl set-hostname "$NEW_HOSTNAME"
else
  echo "$NEW_HOSTNAME" >/etc/hostname
  hostname "$NEW_HOSTNAME"
fi

# Step 4: Reconnect WiFi
echo "[*] Reconnecting WiFi..."
ip link set dev "$IFACE" up
sleep 2

# Refresh DHCP
dhclient -r "$IFACE" 2>/dev/null || true
sleep 2
dhclient "$IFACE" 2>/dev/null || true

echo ""
echo -e "${GREEN}✓ Done!${RESET}"
macchanger -s "$IFACE"
echo "New hostname: $NEW_HOSTNAME"
echo ""
echo "Press any key to restore and exit..."
echo ""

# Wait for user keypress
read -r -s -n 1

exit 0
