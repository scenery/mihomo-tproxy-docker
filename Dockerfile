FROM alpine:latest

ARG TZ="Asia/Shanghai"

WORKDIR /mihomo

RUN echo "Starting..." && \
    sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories && \
    apk update && \
    apk add --no-cache nftables ca-certificates tzdata git && \
    cp /usr/share/zoneinfo/${TZ} /etc/localtime && \
	echo ${TZ} > /etc/timezone && \
    mkdir /mihomo/config && \
    wget -O /mihomo/config/Country.mmdb https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country-lite.mmdb && \
    wget -O /mihomo/config/geosite.dat https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite-lite.dat && \
    git clone -b gh-pages --single-branch https://github.com/MetaCubeX/metacubexd.git /mihomo/config/ui && \
    apk del tzdata git && \
    rm -rf /var/cache/apk/*

COPY --from=metacubex/mihomo:latest /mihomo /mihomo/mihomo
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
CMD ["/mihomo/mihomo", "-d", "/mihomo/config"]