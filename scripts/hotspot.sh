#!/bin/bash

#
# Creating Hostspot and routing through tailscale exit node 
#

# Exit immediately if a command exits with a non-zero status
set -e

# Variables (Customize these before running the script)
SSID="xxxx" # Display name of hostpot network
PASSPHRASE="xxx" # Password for hostspot network
COUNTRY_CODE="xx"  # Use your two-letter country code (e.g., US, GB, IN)
LAN_INTERFACE="eth0"      # The interface connected to the internet (usually eth0)
WLAN_INTERFACE="wlan0"    # The wireless interface to use (usually wlan0)
HOTSPOT_CONFIG_DIR="/etc/hotspot-config"  # Directory to store backup configs
EXIT_NODE_IP=xxxxxx # IP address of tailscale exit node

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo or as root."
    exit 1
fi

# Check if parameter is provided
if [ -z "$1" ]; then
    echo "Usage: sudo ./hotspot.sh [on|off]"
    exit 1
fi

ACTION="$1"

if [ "$ACTION" == "on" ]; then
    echo "Startig to use the tailscale exit node"
    sudo tailscale set --exit-node=$EXIT_NODE_IP --exit-node-allow-lan-access=true

    echo "Turning hotspot ON..."

    # Create backup directory if it doesn't exist
    mkdir -p "$HOTSPOT_CONFIG_DIR"

    # echo "Updating system packages..."
    # apt update && apt upgrade -y

    # echo "Installing required packages..."
    # apt install -y hostapd dnsmasq iptables-persistent

    echo "Stopping services..."
    systemctl stop hostapd
    systemctl stop dnsmasq

    echo "Configuring static IP for $WLAN_INTERFACE using /etc/network/interfaces..."

    # Backup interfaces file
    cp /etc/network/interfaces "$HOTSPOT_CONFIG_DIR/interfaces.backup"

    # Add configuration for wlan0
    grep -qxF "iface $WLAN_INTERFACE inet static" /etc/network/interfaces || cat << EOF >> /etc/network/interfaces

auto $WLAN_INTERFACE
iface $WLAN_INTERFACE inet static
    address 192.168.4.1
    netmask 255.255.255.0
EOF

    echo "Restarting networking service..."
    sudo ifdown $WLAN_INTERFACE || true
    sudo ifup $WLAN_INTERFACE

    echo "Configuring dnsmasq..."
    # Backup dnsmasq.conf
    [ -f /etc/dnsmasq.conf ] && mv /etc/dnsmasq.conf "$HOTSPOT_CONFIG_DIR/dnsmasq.conf.backup"
    cat << EOF > /etc/dnsmasq.conf
interface=$WLAN_INTERFACE      # Use interface $WLAN_INTERFACE
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
EOF

    echo "Configuring hostapd..."
    # Create hostapd.conf
    cat << EOF > /etc/hostapd/hostapd.conf
interface=$WLAN_INTERFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$PASSPHRASE
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
country_code=$COUNTRY_CODE
EOF

    # Update DAEMON_CONF in /etc/default/hostapd
    sed -i.bak "s|^#DAEMON_CONF=.*|DAEMON_CONF=\"/etc/hostapd/hostapd.conf\"|" /etc/default/hostapd
    cp /etc/default/hostapd.bak "$HOTSPOT_CONFIG_DIR/hostapd.default.backup"
    rm /etc/default/hostapd.bak

    echo "Enabling IP forwarding..."
    # Backup sysctl.conf
    cp /etc/sysctl.conf "$HOTSPOT_CONFIG_DIR/sysctl.conf.backup"
    sed -i "s|^#net.ipv4.ip_forward=1|net.ipv4.ip_forward=1|" /etc/sysctl.conf
    sysctl -p

    echo "Configuring iptables..."
    iptables -F
    iptables -t nat -F

    iptables -t nat -A POSTROUTING -o tailscale0 -j MASQUERADE
    iptables -A FORWARD -i $WLAN_INTERFACE -o tailscale0 -j ACCEPT
    iptables -A FORWARD -i tailscale0 -o $WLAN_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT

    echo "Saving iptables rules..."
    netfilter-persistent save

    echo "Starting services..."
    systemctl unmask hostapd
    systemctl start hostapd
    systemctl start dnsmasq

    echo "Enabling services to start on boot..."
    systemctl enable hostapd
    systemctl enable dnsmasq

    curl https://ifconfig.co/json | grep -e '"ip"' -e '"country"'
    echo "Hotspot is now ON."
    

elif [ "$ACTION" == "off" ]; then
    echo "Turning hotspot OFF..."

    echo "Switching off tailscale exit node"
    sudo tailscale set --exit-node= --exit-node-allow-lan-access=false

    echo "Stopping services..."
    systemctl stop hostapd
    systemctl stop dnsmasq

    echo "Disabling services..."
    systemctl disable hostapd
    systemctl disable dnsmasq

    echo "Restoring network configuration..."
    # Restore interfaces file
    if [ -f "$HOTSPOT_CONFIG_DIR/interfaces.backup" ]; then
        cp "$HOTSPOT_CONFIG_DIR/interfaces.backup" /etc/network/interfaces
    else
        # Remove static IP configuration for wlan0
        sed -i "/auto $WLAN_INTERFACE/,+3d" /etc/network/interfaces
    fi

    echo "Restarting network services..."
    # Attempt to restart network services that may manage wlan0
    if systemctl is-active --quiet dhcpcd; then
        systemctl restart dhcpcd
    elif systemctl is-active --quiet NetworkManager; then
        systemctl restart NetworkManager
    else
        echo "No network manager detected, bringing interface down and up manually."
        ip link set $WLAN_INTERFACE down
        ip link set $WLAN_INTERFACE up
    fi

    echo "Restoring dnsmasq configuration..."
    if [ -f "$HOTSPOT_CONFIG_DIR/dnsmasq.conf.backup" ]; then
        mv "$HOTSPOT_CONFIG_DIR/dnsmasq.conf.backup" /etc/dnsmasq.conf
    else
        rm -f /etc/dnsmasq.conf
    fi

    echo "Restoring hostapd configuration..."
    if [ -f "$HOTSPOT_CONFIG_DIR/hostapd.default.backup" ]; then
        mv "$HOTSPOT_CONFIG_DIR/hostapd.default.backup" /etc/default/hostapd
    else
        sed -i "s|^DAEMON_CONF=.*|#DAEMON_CONF=\"\"|" /etc/default/hostapd
    fi
    rm -f /etc/hostapd/hostapd.conf

    echo "Disabling IP forwarding..."
    # Restore sysctl.conf
    if [ -f "$HOTSPOT_CONFIG_DIR/sysctl.conf.backup" ]; then
        mv "$HOTSPOT_CONFIG_DIR/sysctl.conf.backup" /etc/sysctl.conf
    else
        sed -i "s|^net.ipv4.ip_forward=1|#net.ipv4.ip_forward=1|" /etc/sysctl.conf
    fi
    sysctl -p

    echo "Flushing iptables rules..."
    iptables -F
    iptables -t nat -F

    echo "Saving iptables rules..."
    netfilter-persistent save
    
    curl https://ifconfig.co/json | grep -e '"ip"' -e '"country"'
    echo "Hotspot is now OFF."

else
    echo "Invalid option: $ACTION"
    echo "Usage: sudo ./hotspot.sh [on|off]"
    exit 1
fi