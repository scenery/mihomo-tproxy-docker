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
    # Avoid circular redirect
    nft add rule clash PREROUTING mark 0xff return
    # Mark all other packets as 1 and forward to port 7893
    nft add rule clash PREROUTING meta l4proto {tcp, udp} mark set 1 tproxy to :7893 accept
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
    fi
    # Redirect connected requests to optimize TPROXY performance
    nft add chain clash DIVERT { type filter hook prerouting priority -150 \; }
    nft add rule clash DIVERT meta l4proto tcp socket transparent 1 meta mark set 1 accept
}

setup_iptables() {
    set -ex
    # Create a new chain
    iptables -t mangle -N CLASH
    # Skip packets to local/private address
    iptables -t mangle -A CLASH -d 0.0.0.0/8 -j RETURN
    iptables -t mangle -A CLASH -d 10.0.0.0/8 -j RETURN
    iptables -t mangle -A CLASH -d 127.0.0.0/8 -j RETURN
    iptables -t mangle -A CLASH -d 169.254.0.0/16 -j RETURN
    iptables -t mangle -A CLASH -d 172.16.0.0/12 -j RETURN
    iptables -t mangle -A CLASH -d 192.168.0.0/16 -j RETURN
    iptables -t mangle -A CLASH -d 224.0.0.0/4 -j RETURN
    iptables -t mangle -A CLASH -d 240.0.0.0/4 -j RETURN
    # Avoid circular redirect
    iptables -t mangle -A CLASH -j RETURN -m mark --mark 0xff
    # Mark all other packets as 1 and forward to port 7893
    iptables -t mangle -A CLASH -p tcp -j TPROXY --on-port 7893 --tproxy-mark 1
    iptables -t mangle -A CLASH -p udp -j TPROXY --on-port 7893 --tproxy-mark 1
    # Apply rules
    iptables -t mangle -A PREROUTING -j CLASH
    # Disable QUIC (UDP 443)
    if [ "$QUIC" = "false" ]; then
        iptables -A INPUT -p udp -m udp --dport 443 -j REJECT --reject-with icmp-port-unreachable
    fi
    # Forward local traffic
    if [ "$CONTAINER_PROXY" = "true" ]; then
        iptables -t mangle -N CLASH_LOCAL
        iptables -t mangle -A CLASH_LOCAL -d 0.0.0.0/8 -j RETURN
        iptables -t mangle -A CLASH_LOCAL -d 10.0.0.0/8 -j RETURN
        iptables -t mangle -A CLASH_LOCAL -d 127.0.0.0/8 -j RETURN
        iptables -t mangle -A CLASH_LOCAL -d 169.254.0.0/16 -j RETURN
        iptables -t mangle -A CLASH_LOCAL -d 172.16.0.0/12 -j RETURN
        iptables -t mangle -A CLASH_LOCAL -d 192.168.0.0/16 -j RETURN
        iptables -t mangle -A CLASH_LOCAL -d 224.0.0.0/4 -j RETURN
        iptables -t mangle -A CLASH_LOCAL -d 240.0.0.0/4 -j RETURN
        iptables -t mangle -A CLASH_LOCAL -j RETURN -m mark --mark 0xff
        iptables -t mangle -A CLASH_LOCAL -p udp -j MARK --set-mark 1
        iptables -t mangle -A CLASH_LOCAL -p tcp -j MARK --set-mark 1
        iptables -t mangle -A OUTPUT -j CLASH_LOCAL
    fi
    # Redirect connected requests to optimize TPROXY performance
    iptables -t mangle -N DIVERT
    iptables -t mangle -A DIVERT -j MARK --set-mark 1
    iptables -t mangle -A DIVERT -j ACCEPT
    iptables -t mangle -I PREROUTING -p tcp -m socket -j DIVERT
}

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

if [ "$TABLES" = "nftables" ]; then
    echo "Using nftables..."
    setup_nftables
elif [ "$TABLES" = "iptables" ]; then
    echo "Using iptables..."
    setup_iptables
else
    echo "Error: '\$TABLES' Must be 'nftables' or 'iptables'."
    exit 1
fi

echo "*** Starting Mihomo ***"
exec "$@"