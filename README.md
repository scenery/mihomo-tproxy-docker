# Mihomo Transparent Proxy Docker

A simple Mihomo (formerly known as Clash.Meta) transparent proxy Docker image.

You can build and deploy this image on your local Linux device (such as a Raspberry Pi or NAS) as a bypass gateway. Support both TCP and UDP redirecting using nftables/iptables, with the option to block QUIC (UDP 443) traffic. Since it runs within a Docker container, there's no need to worry about affecting the host network.

## Getting started

*\* Unless you need network isolation, this is not a recommended practice for general use. Running in a Docker container may incur some network overhead.*

By default, the gateway itself (docker container) does not forward traffic to TPROXY. If you are using the redir-host mode and do not have a clean DNS server that can be directly connected to, consider setting `CONTAINER_PROXY` to `true` within the `docker-compose.yaml` file.

If IPv6 usage is required, please edit your Docker configuration, macvlan configuration, and relevant sections in the `entrypoint.sh` file. Further detailed explanations will not be provided here.

### Requirements

- AMD64 or ARM64 (AArch64) based Linux devices
- Docker and Compose V2 installed

### Building

Download or clone this repository to your local machine, and then build the image using the following command:

```
docker build -t mihomo:latest .
```

By default, the image uses nftables. If you prefer iptables, run the following command instead:

```
docker build --build-arg TABLES=iptables -t mihomo:latest .
```

Please note: To minimize image size, only one of nftables and iptables will be installed, and it must match the configuration in the provided  `docker-compose.yaml` file.

## Usage

Configure  `docker-compose.yaml` file:

```docker
services:
  mihomo:
    image: mihomo:latest
    # build:
    #   context: .
    #   dockerfile: Dockerfile
    container_name: mihomo
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    networks:
      homenet:
        ipv4_address: 192.168.31.32
    environment:
      TABLES: "nftables" # nftables or iptables (must match --build-arg)
      QUIC: "true" # allow quic (udp 443)
      CONTAINER_PROXY: "false" # forward the container's own traffic to tproxy
    volumes:
      - './config.yaml:/mihomo/config/config.yaml'

networks:
  mihomovlan:
    name: mihomovlan
    driver: macvlan
    driver_opts:
      parent: eth0 # modify this to match your network interface name
    ipam:
      config: # modify the following content to match your local network env
        - subnet: "192.168.2.0/24"
          ip_range: "192.168.2.64/26"
          gateway: "192.168.2.1"
```

!!! Configure  `config.yaml` of mihomo before you start the container. Please refer to the comments in the configuration for modifications.

After configuring the `config.yaml` file, to start the container:

```
docker compose up
```

If there are no errors, press Ctrl + C to stop the container. Then restart it in the background:

```
docker compose up -d
```

Finally, change the gateway and DNS server on your PC or phone to the Docker container's IP address. (e.g., 192.168.2.2).

If everything is correct, you should be able to browse the internet now. You can conveniently manage mihomo via the built-in [web dashboard](https://github.com/MetaCubeX/metacubexd) accessible at http://192.168.2.2:9090.

## Credits

- [Dreamacro/clash](https://github.com/Dreamacro/clash)
- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)
