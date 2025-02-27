# Mihomo Transparent Proxy Docker

A simple Mihomo (formerly known as Clash.Meta) transparent proxy Docker image.

You can build and deploy this image on your local Linux device, such as a Raspberry Pi or NAS, as a bypass gateway. It supports both TCP and UDP redirection using nftables, with the option to block QUIC (UDP 443) traffic and bypass forwarding CN IPs to the Mihomo kernel. Since it runs within a Docker container, there's no need to worry about affecting the host network.

## Getting started

*\* Unless you need network isolation, this is not a recommended practice for general use. Running in a Docker container may incur some network overhead.*

By default, the gateway itself (docker container) does not forward traffic to TPROXY. If you are using the redir-host mode and do not have a clean DNS server that can be directly connected to, consider setting `CONTAINER_PROXY` to `true` within the `docker-compose.yaml` file.

### Requirements

- AMD64 or ARM64 (AArch64) based Linux devices
- Docker and Compose V2 installed

### Building

Download or clone this repository to your local machine, and then build the image using the following command:

```
docker build -t mihomo:latest .
```

If you encounter network issues during the build process, try using the host network mode:

```
docker build --network=host -t mihomo:latest .
```

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
      mihomovlan:
        ipv4_address: 192.168.2.2
    environment:
      QUIC: "true" # allow quic (udp 443)
      CONTAINER_PROXY: "false" # forward the container's own traffic to tproxy
      SKIP_CNIP: "false" # bypass forwarding cn ip to the mihomo kernel (only valid for redir-host mode)
    volumes:
      - './config.yaml:/mihomo/config/config.yaml'
      - './cn_cidr.txt:/mihomo/config/cn_cidr.txt'

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

If you need to connect to an IPv6 server, modify the networks config as follows:
```
networks:
  mihomovlan:
    name: mihomovlan
    driver: macvlan
    driver_opts:
      parent: eth0
    enable_ipv6: true
    ipam:
      config:
        - subnet: "192.168.2.0/24"
          ip_range: "192.168.2.64/26"
          gateway: "192.168.2.1"
        - subnet: "2001:db8:1::/64"
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

You can download the latest [CN IP list](https://github.com/misakaio/chnroutes2/blob/master/chnroutes.txt) and replace the `cn_cidr.txt` file with it (the filename cannot be changed). After updating the `config.yaml` or `cn_cidr.txt`, simply restart the Docker container for the changes to take effect:

```
docker compose restart
```

*\* Setting up a crontab scheduled task for automatic updating and restarting is usually a good idea.*

Finally, change the gateway and DNS server on your PC or phone to the Docker container's IP address. (e.g., 192.168.2.2).

If everything is correct, you should be able to browse the internet now. You can conveniently manage mihomo via the built-in [web dashboard](https://github.com/MetaCubeX/metacubexd) accessible at http://192.168.2.2:9090.

## Credits

- [Dreamacro/clash](https://github.com/Dreamacro/clash)
- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)
- [misakaio/chnroutes2](https://github.com/misakaio/chnroutes2)
