#!/bin/sh
# Reference documentation:
# https://www.kernel.org/doc/Documentation/networking/tproxy.txt
# https://guide.v2fly.org/app/tproxy.html

# configs
MIHOMO_PORT=7893
MIHOMO_DNS_PORT=1053
MIHOMO_MARK=0xff
TPROXY_MARK=0x1
ROUTE_TABLE=100

CN_IP_FILE="/mihomo/config/cn_cidr.txt"

NFT_DIR="/mihomo/nftables"
MAIN_NFT="$NFT_DIR/clash.nft"
PRIVATE_NFT="$NFT_DIR/private.nft"
CHNROUTE_NFT="$NFT_DIR/chnroute.nft"

DEFAULT_IFACE=$(ip route | awk '/^default/ {print $5; exit}')
[ -z "$DEFAULT_IFACE" ] && DEFAULT_IFACE="eth0"

RESERVED_IPS="0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4"

setup_nftables() {
    nft flush ruleset
    set -e

    # Generate nftables rules
    mkdir -p "$NFT_DIR"

    # private.nft
    cat > "$PRIVATE_NFT" <<EOF
table ip clash {
  set reserved_ips {
    type ipv4_addr;
    flags interval;
    elements = {
EOF

    for ip in $RESERVED_IPS; do
        echo "      $ip," >> "$PRIVATE_NFT"
    done
    sed -i '$ s/,$//' "$PRIVATE_NFT"

    cat >> "$PRIVATE_NFT" <<EOF
    }
  }
}
EOF

    # chnroute.nft
    if [ "$BYPASS_CN" = "true" ] && [ -f "$CN_IP_FILE" ]; then
        cat > "$CHNROUTE_NFT" <<EOF
table ip clash {
  set cn_ips {
    type ipv4_addr;
    flags interval;
    elements = {
EOF

        awk '!/^#/ && NF { gsub(/\r/, ""); printf "      %s,\n", $1 }' "$CN_IP_FILE" >> "$CHNROUTE_NFT"
        sed -i '$ s/,$//' "$CHNROUTE_NFT"

        cat >> "$CHNROUTE_NFT" <<EOF
    }
  }
}
EOF
    else
        echo "CN bypass disabled or file not found: $CN_IP_FILE"
        rm -f "$CHNROUTE_NFT"
    fi

    # clash.nft
    cat > "$MAIN_NFT" <<EOF
flush ruleset

include "$PRIVATE_NFT"
EOF

    [ "$BYPASS_CN" = "true" ] && [ -f "$CN_IP_FILE" ] && echo "include \"$CHNROUTE_NFT\"" >> "$MAIN_NFT"

    cat >> "$MAIN_NFT" <<EOF

table ip clash {
  chain PREROUTING {
    type filter hook prerouting priority filter; policy accept;
    ip daddr @reserved_ips return
EOF

    [ "$BYPASS_CN" = "true" ] && [ -f "$CN_IP_FILE" ] && echo "    ip daddr @cn_ips return" >> "$MAIN_NFT"

    cat >> "$MAIN_NFT" <<EOF
    meta mark $MIHOMO_MARK return
    meta l4proto {tcp, udp} mark set $TPROXY_MARK tproxy to 127.0.0.1:$MIHOMO_PORT accept
  }

  chain PREROUTING_DNS {
    type nat hook prerouting priority -100; policy accept;
    meta mark $MIHOMO_MARK return
    udp dport 53 redirect to :$MIHOMO_DNS_PORT
  }

  chain DIVERT {
    type filter hook prerouting priority -150; policy accept;
    meta l4proto tcp socket transparent 1 meta mark set $TPROXY_MARK accept
  }
EOF

    if [ "$QUIC" = "false" ]; then
        cat >> "$MAIN_NFT" <<EOF

  chain INPUT {
    type filter hook input priority -50;
    udp dport 443 reject
  }
EOF
    fi

    if [ "$CONTAINER_PROXY" = "true" ]; then
        cat >> "$MAIN_NFT" <<EOF

  chain OUTPUT {
    type route hook output priority -150; policy accept;
    ip daddr @reserved_ips return
    meta mark $MIHOMO_MARK return
    meta l4proto {tcp, udp} mark set $TPROXY_MARK accept
  }

  chain OUTPUT_DNS {
    type nat hook output priority -100; policy accept;
    meta mark $MIHOMO_MARK return
    udp dport 53 redirect to :$MIHOMO_DNS_PORT
  }
EOF
    fi

    echo "}" >> "$MAIN_NFT"

    # return to nat
    cat >> "$MAIN_NFT" <<EOF

table ip nat {
  chain POSTROUTING {
    type nat hook postrouting priority 100; policy accept;
    oifname "$DEFAULT_IFACE" masquerade
  }
}
EOF

    nft -f "$MAIN_NFT"
}

if [ "$BYPASS_CN" != "true" ] && [ "$BYPASS_CN" != "false" ]; then
    echo "Error: '\$BYPASS_CN' Must be 'true' or 'false'."
    exit 1
fi

if [ "$QUIC" != "true" ] && [ "$QUIC" != "false" ]; then
    echo "Error: '\$QUIC' Must be 'true' or 'false'."
    exit 1
fi

if [ "$CONTAINER_PROXY" != "true" ] && [ "$CONTAINER_PROXY" != "false" ]; then
    echo "Error: '\$CONTAINER_PROXY' Must be 'true' or 'false'."
    exit 1
fi

# Add policy routing to packets marked as 1 delivered locally
if ! ip rule list | grep -q "fwmark $TPROXY_MARK lookup $ROUTE_TABLE"; then
    ip rule add fwmark $TPROXY_MARK lookup $ROUTE_TABLE
fi

if ! ip route show table $ROUTE_TABLE | grep -q "local default dev lo"; then
    ip route add local default dev lo table $ROUTE_TABLE
fi

setup_nftables

echo "*** Starting Mihomo ***"
exec "$@"