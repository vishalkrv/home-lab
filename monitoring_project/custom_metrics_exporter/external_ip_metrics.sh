#!/bin/bash
# This script generates Prometheus metrics for external connections.

# Node Exporter's textfile collector directory
# This will be mounted from the host into the container.
METRICS_FILE="/var/lib/node_exporter/textfile_collector/external_connections.prom"
TAILSCALE_INTERFACE="tailscale0" # Common Tailscale interface name

# Get local Tailscale IP for filtering
TAILSCALE_IP=$(ip -4 addr show dev $TAILSCALE_INTERFACE 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1)

# Get a list of all local IPs, including loopback and Tailscale
LOCAL_IPS=$(ip -4 addr show | grep inet | awk '{print $2}' | cut -d/ -f1 | tr '\n' ' ')
LOCAL_IPS_REGEX="^(127\.|0\.0\.0\.0|$TAILSCALE_IP)" # Add common local/any-bind IPs

declare -A external_ips_count # For counting unique external IPs
declare -A connections_by_port # For counting connections per local port

# Clear previous metrics file to ensure only current data is present
> "$METRICS_FILE.tmp"

# Iterate through established TCP and UDP connections
# -t: TCP, -u: UDP, -n: numeric, -p: process, -a: all
ss -tunap | while read -r line; do
    # Filter for established TCP/UDP connections
    if [[ $line =~ ^(tcp|udp) && ($line =~ ESTAB || $line =~ LISTEN || $line =~ UNCONN) ]]; then # Include LISTEN for full picture, UNCONN for UDP
        local_addr_port=$(echo "$line" | awk '{print $5}')
        remote_addr_port=$(echo "$line" | rev | cut -d: -f2- | rev)

        # Extract just the IP addresses and ports
        local_ip=$(echo "$local_addr_port" | rev | cut -d: -f2- | rev)
        local_port=$(echo "$local_addr_port" | rev | cut -d: -f1 | rev)
        remote_ip=$(echo "$remote_addr_port" | rev | cut -d: -f2- | rev)

        # Skip connections where remote IP is empty (e.g., LISTEN state without a peer)
        if [[ -z "$remote_ip" ]]; then
            continue
        fi

        # Skip connections where remote IP is local (loopback, self, Tailscale, internal network)
        is_local_connection=false
        for ip in $LOCAL_IPS; do
            if [[ "$remote_ip" == "$ip" ]]; then
                is_local_connection=true
                break
            fi
        done

        # Also filter out well-known private IP ranges, as they're usually internal
        if [[ "$remote_ip" =~ ^10\. || "$remote_ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. || "$remote_ip" =~ ^192\.168\. ]]; then
            is_local_connection=true
        fi

        # Skip if the remote IP is effectively local or handled by Tailscale
        if [[ "$is_local_connection" == true || "$remote_ip" =~ $LOCAL_IPS_REGEX ]]; then
            continue
        fi

        # If it passed all filters, consider it an external connection
        # Only count unique IPs
        external_ips_count["$remote_ip"]=1
        connections_by_port["$local_port"]=$((connections_by_port["$local_port"] + 1))
    fi
done

# Generate Prometheus metrics
echo "# HELP node_external_connections_total Total number of unique external IP addresses connected." >> "$METRICS_FILE.tmp"
echo "# TYPE node_external_connections_total gauge" >> "$METRICS_FILE.tmp"
echo "node_external_connections_total ${#external_ips_count[@]}" >> "$METRICS_FILE.tmp"

echo "# HELP node_external_connections_by_port_total Total number of external connections per local port." >> "$METRICS_FILE.tmp"
echo "# TYPE node_external_connections_by_port_total gauge" >> "$METRICS_FILE.tmp"
for port in "${!connections_by_port[@]}"; do
    echo "node_external_connections_by_port_total{port=\"$port\"} ${connections_by_port["$port"]}" >> "$METRICS_FILE.tmp"
done

mv "$METRICS_FILE.tmp" "$METRICS_FILE"