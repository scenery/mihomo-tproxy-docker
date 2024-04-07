FROM alpine:latest

ARG TZ="Asia/Shanghai"

WORKDIR /mihomo

RUN echo "Starting..." && \
    sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories && \
    apk update && \
    apk add --no-cache nftables ca-certificates tzdata unzip && \
    cp /usr/share/zoneinfo/${TZ} /etc/localtime && \
	echo ${TZ} > /etc/timezone && \
    mkdir /mihomo/config && \
    wget -O /mihomo/config/Country.mmdb https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country-lite.mmdb && \
    wget -O /mihomo/config/geosite.dat https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite-lite.dat && \
    # git clone -b gh-pages --single-branch https://github.com/MetaCubeX/metacubexd.git /mihomo/config/ui && \
    wget https://mirror.ghproxy.com/https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip && \
    unzip gh-pages.zip -d /mihomo/config && \
    mv /mihomo/config/metacubexd-gh-pages /mihomo/config/ui && \
    rm gh-pages.zip && \
    apk del tzdata unzip && \
    rm -rf /var/cache/apk/*

COPY --from=metacubex/mihomo:latest /mihomo /mihomo/mihomo
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
CMD ["/mihomo/mihomo", "-d", "/mihomo/config"]