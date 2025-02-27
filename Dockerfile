FROM alpine:latest

ARG TZ="Asia/Shanghai"

WORKDIR /mihomo

RUN echo "Starting..." && \
    apk add --no-cache nftables ca-certificates tzdata git && \
    cp /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone && \
    mkdir /mihomo/config && \
    git clone -b gh-pages --single-branch https://github.com/MetaCubeX/metacubexd.git /mihomo/config/ui && \
    apk del tzdata git && \
    rm -rf /var/cache/apk/*

COPY --from=metacubex/mihomo:latest /mihomo /mihomo/mihomo
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
CMD ["/mihomo/mihomo", "-d", "/mihomo/config"]
