#!/bin/sh
# Reference documentation:
# https://www.kernel.org/doc/Documentation/networking/tproxy.txt
# https://guide.v2fly.org/app/tproxy.html

setup_nftables() {
    nft flush ruleset
    set -ex
    # Create a new table
    nft add table clash
    nft add chain clash PREROUTING { type filter hook prerouting priority 0 \; }

    # Skip packets to local/private address
    nft add rule clash PREROUTING ip daddr {0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4} return
    # Skip CN IP address
    if [ "$SKIP_CNIP" = "true" ]; then
        CN_IP=$(awk '!/^#/ {ip=ip $1 ", "} END {sub(/, $/, "", ip); print ip}' /mihomo/config/cn_cidr.txt)
        nft add rule clash PREROUTING ip daddr {$CN_IP} return
    fi

    # Avoid circular redirect
    nft add rule clash PREROUTING mark 0xff return
    # Mark all other packets as 1 and forward to port 7893
    nft add rule clash PREROUTING meta l4proto {tcp, udp} mark set 1 tproxy to :7893 accept

    # DNS
    nft add chain clash PREROUTING_DNS { type nat hook prerouting priority -100 \; }
    nft add rule clash PREROUTING_DNS meta mark 0xff return
    nft add rule clash PREROUTING_DNS udp dport 53 redirect to :1053

    # Disable QUIC (UDP 443)
    if [ "$QUIC" = "false" ]; then
        nft add chain clash INPUT { type filter hook input priority 0 \; }
        nft add rule clash INPUT udp dport 443 reject
    fi

    # Forward local traffic
    if [ "$CONTAINER_PROXY" = "true" ]; then
        nft add chain clash OUTPUT { type route hook output priority 0 \; }
        nft add rule clash OUTPUT ip daddr {0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4} return
        nft add rule clash OUTPUT mark 0xff return
        nft add rule clash OUTPUT meta l4proto {tcp, udp} mark set 1 accept
        # DNS
        nft add chain clash OUTPUT_DNS { type nat hook output priority -100 \; }
        nft add rule clash OUTPUT_DNS meta mark 0xff return
        nft add rule clash OUTPUT_DNS udp dport 53 redirect to :1053
    fi

    # Redirect connected requests to optimize TPROXY performance
    nft add chain clash DIVERT { type filter hook prerouting priority -150 \; }
    nft add rule clash DIVERT meta l4proto tcp socket transparent 1 meta mark set 1 accept
}

if [[ "$SKIP_CNIP" != "true" && "$SKIP_CNIP" != "false" ]]; then
    echo "Error: '\$SKIP_CNIP' Must be 'true' or 'false'."
    exit 1
fi

if [[ "$QUIC" != "true" && "$QUIC" != "false" ]]; then
    echo "Error: '\$QUIC' Must be 'true' or 'false'."
    exit 1
fi

if [[ "$CONTAINER_PROXY" != "true" && "$QUIC" != "false" ]]; then
    echo "Error: '\$CONTAINER_PROXY' Must be 'true' or 'false'."
    exit 1
fi

# Add policy routing to packets marked as 1 delivered locally
ip rule add fwmark 1 lookup 100
ip route add local 0.0.0.0/0 dev lo table 100

setup_nftables

echo "*** Starting Mihomo ***"
exec "$@"