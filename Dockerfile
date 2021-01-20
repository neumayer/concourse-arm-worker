FROM golang:1.14.3-alpine3.11 as builder
ENV GO111MODULE=on
ENV CONCOURSE_VERSION=v6.5.1
ENV GUARDIAN_COMMIT=51480bc73a282c02f827dde4851cc12265774272
ENV CNI_PLUGINS_VERSION=v0.8.6
RUN apk add gcc git g++

RUN git clone https://github.com/cloudfoundry/guardian.git /go/guardian
WORKDIR /go/guardian
RUN git checkout $GUARDIAN_COMMIT
RUN go build -ldflags "-extldflags '-static'" -mod=vendor -o gdn ./cmd/gdn
WORKDIR /go/guardian/cmd/init
RUN gcc -static -o init init.c ignore_sigchild.c

RUN git clone --branch $CONCOURSE_VERSION https://github.com/concourse/concourse /go/concourse
WORKDIR /go/concourse
RUN go build -ldflags "-extldflags '-static'" ./cmd/concourse

RUN git clone --branch $CNI_PLUGINS_VERSION https://github.com/containernetworking/plugins.git /go/plugins
WORKDIR /go/plugins
RUN apk add bash
ENV CGO_ENABLED=0
RUN ./build_linux.sh

FROM ubuntu:bionic AS ubuntu
COPY --from=0 /go/concourse/concourse /usr/local/concourse/bin/
COPY --from=0 /go/guardian/gdn /usr/local/concourse/bin/
COPY --from=0 /go/guardian/cmd/init/init /usr/local/concourse/bin/
COPY --from=0 /go/plugins/bin/* /usr/local/concourse/bin/
# add resource-types
COPY resource-types /usr/local/concourse/resource-types

# auto-wire work dir for 'worker' and 'quickstart'
ENV CONCOURSE_WORK_DIR                /worker-state
ENV CONCOURSE_WORKER_WORK_DIR         /worker-state

# volume for non-aufs/etc. mount for baggageclaim's driver
VOLUME /worker-state

RUN apt-get update && apt-get install -y \
    btrfs-tools \
    ca-certificates \
    containerd \
    iptables \
    dumb-init \
    iproute2 \
    file

STOPSIGNAL SIGUSR2

ADD https://raw.githubusercontent.com/concourse/concourse-docker/486894e6d6f84aad112c14094bca18bec8c48154/entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["dumb-init", "/usr/local/bin/entrypoint.sh"]
