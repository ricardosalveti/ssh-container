FROM alpine:3.13 as systemd

RUN apk update && apk add --no-cache \
        bash git autoconf file g++ gcc libc-dev make pkgconf python3 ninja util-linux \
        pciutils usbutils coreutils binutils findutils grep build-base abuild \
        binutils binutils-doc gcc-doc gperf libcap libcap-dev valgrind-dev meson \
        util-linux-dev libmount musl-libintl libintl xz-dev

RUN cd /tmp && git clone https://github.com/ricardosalveti/systemd-stable.git systemd && \
    cd systemd && git checkout v247-stable-musl

RUN cd /tmp/systemd && \
    CFLAGS=" -D__UAPI_DEF_ETHHDR=0 " meson \
        -Dnetworkd=false -Dgshadow=false -Didn=false -Dlocaled=false \
        -Dnss-myhostname=false -Dnss-systemd=false -Dnss-mymachines=false \
        -Dnss-resolve=false -Dsysusers=false -Duserdb=false -Dutmp=false \
        -Dlogind=false -Dfirstboot=false -Dxdg-autostart=false -Dhostnamed=false \
        -Dtimedated=false -Dpolkit=false -Dresolve=false -Dsmack=false build \
    && \
    ninja -C build && \
    cp -v build/journalctl /usr/bin && \
        strip /usr/bin/journalctl && \
    cp -v build/src/shared/libsystemd-shared-247.so /lib && \
        strip /lib/libsystemd-shared-247.so && \
    rm -rf /tmp/systemd

FROM alpine:3.13 as facette

RUN apk update && apk add --no-cache git && \
    mkdir -p /root/go/src/facette.io && \
    git clone https://github.com/facette/facette.git /root/go/src/facette.io/facette && \
    cd /root/go/src/facette.io/facette && git reset --hard 202a9990c4a03e633b1af8495019f82763f67e5c

RUN apk --no-cache add go make musl-dev nodejs rrdtool-dev yarn && \
    GOBIN=/usr/local/bin go get github.com/jteeuwen/go-bindata/... && \
    make TAGS="skip_docs" -C /root/go/src/facette.io/facette build install && \
    install -D /root/go/src/facette.io/facette/docs/examples/facette.yaml /etc/facette/facette.yaml && \
    sed -i -r \
        -e "s|listen: localhost:12003|listen: :12003|" \
        -e "s|path: var/data.db|path: /var/lib/facette/data.db|" \
        -e "s|path: var/cache|path: /var/cache/facette|" \
        /etc/facette/facette.yaml && \
    rm -rf /root/go

FROM alpine:3.13

LABEL maintainer="ricardo@foundries.io"

ARG OVERLAY_VERSION="v2.2.0.3"

RUN set -x && apk add --no-cache curl coreutils tzdata shadow && \
    case "`uname -m`" in \
        x86_64) S6_ARCH='amd64';; \
        armv7l) S6_ARCH='armhf';; \
        aarch64) S6_ARCH='aarch64';; \
        *) echo "unsupported architecture"; exit 1 ;; \
    esac && \
    curl -L -s https://github.com/just-containers/s6-overlay/releases/download/${OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.gz | tar xvzf - -C / && \
    groupmod -g 911 users && \
    useradd -u 911 -U -d /config -s /bin/false abc && \
    usermod -G users abc && \
    mkdir -p /app /config /defaults && \
    apk del --purge && \
    rm -rf /tmp/*

RUN apk update && apk add --no-cache \
    bash git libcap libmount ca-certificates rrdtool

COPY --from=systemd /usr/bin/journalctl /usr/bin/journalctl
COPY --from=systemd /lib/libsystemd-shared-247.so /lib/libsystemd-shared-247.so
COPY --from=facette /usr/local/bin /usr/local/bin
COPY --from=facette /etc/facette /etc/facette

RUN adduser -h /var/lib/facette -S -D -u 1234 facette

RUN apk add --no-cache --upgrade \
        logrotate nano sudo \
        openssh-client openssh-server openssh-sftp-server \
    && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config && \
    usermod --shell /bin/bash abc && \
    rm -rf /tmp/*

# add local files
COPY root /

ENTRYPOINT ["/init"]
