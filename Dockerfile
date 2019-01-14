FROM debian:stretch

RUN apt-get update && \
  apt-get -y install nginx libnginx-mod-http-dav-ext \
      libnginx-mod-http-lua luarocks libcap2-bin && \
  rm -rf /var/lib/apt/lists/*

RUN addgroup --system nginx \
    && adduser --system --disabled-password --home /var/cache/nginx \
    --shell /sbin/nologin --ingroup nginx nginx

RUN ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log

RUN luarocks install ljsyscall

ADD rootfs/ /
ADD davt.lua /etc/nginx/scripts/davt.lua
EXPOSE 80

CMD ["/bin/bash", "/run.sh"]
