#!/bin/bash
# Spoofs MAC address and hostname and restores to previous state upon exiting.

clear

echo "░█▀▀░█░█░█▀█░█▀█░█▀▀░█▀▀░█░█░▀█▀░█▀▀░▀█▀░█▀▀░█▀▄"
echo "░▀▀█░█▀█░█▀█░█▀▀░█▀▀░▀▀█░█▀█░░█░░█▀▀░░█░░█▀▀░█▀▄"
echo "░▀▀▀░▀░▀░▀░▀░▀░░░▀▀▀░▀▀▀░▀░▀░▀▀▀░▀░░░░▀░░▀▀▀░▀░▀"

set -euo pipefail

RED='\033[1;31m'
GREEN='\033[1;32m'
RESET='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "Shapeshifter must be ${RED}run as root${RESET}" >&2
  exit 1
fi

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

OLD_HOSTNAME_FILE="/tmp/old_hostname"
hostname >"$OLD_HOSTNAME_FILE" || true
OLD_HOSTNAME=$(cat "$OLD_HOSTNAME_FILE")

NEW_HOSTNAME="anon-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' ')"

echo "Interface: $IFACE"
echo "Old hostname: $OLD_HOSTNAME"

# Cleanup function - restores original state
cleanup() {
  echo "\n%s\n" "[*] Restoring original MAC and hostname..."

  ip link set dev "$IFACE" down 2>/dev/null || true
  sleep 1

  macchanger -p "$IFACE" >/dev/null 2>&1 || true

  # Restore hostname
  if command -v hostnamectl &>/dev/null; then
    hostnamectl set-hostname "$OLD_HOSTNAME"
  else
    echo "$OLD_HOSTNAME" >/etc/hostname
    hostname "$OLD_HOSTNAME"
  fi

  ip link set dev "$IFACE" up 2>/dev/null || true
  sleep 2

  # Refresh DHCP
  dhclient -r "$IFACE" 2>/dev/null || true
  sleep 2
  dhclient "$IFACE" 2>/dev/null || true

  echo -e "${GREEN}✓ Restored!${RESET}"
  echo "Hostname: $OLD_HOSTNAME"
}

# Run cleanup on exit
trap cleanup EXIT

echo "[*] Disconnecting WiFi..."
ip link set dev "$IFACE" down
sleep 1

echo "[*] Changing MAC address (random)..."
macchanger -r "$IFACE"

echo "[*] Changing hostname to $NEW_HOSTNAME..."
if command -v hostnamectl &>/dev/null; then
  hostnamectl set-hostname "$NEW_HOSTNAME"
else
  echo "$NEW_HOSTNAME" >/etc/hostname
  hostname "$NEW_HOSTNAME"
fi

echo "[*] Reconnecting WiFi..."
ip link set dev "$IFACE" up
sleep 2

dhclient -r "$IFACE" 2>/dev/null || true
sleep 2
dhclient "$IFACE" 2>/dev/null || true

echo -e "\n%s\n" "${GREEN}✓ Done!${RESET}"
macchanger -s "$IFACE"
echo "New hostname: $NEW_HOSTNAME"
echo "\n%s\n" "Press any key to restore and exit..."

# Wait for user keypress
read -r -s -n 1

exit 0
