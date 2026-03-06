FROM rust:alpine AS builder
WORKDIR /app

RUN apk add --no-cache build-base musl-dev pkgconfig

COPY rustpipe/Cargo.toml ./
COPY rustpipe/Cargo.lock ./
COPY rustpipe/src ./src
RUN cargo build --release --locked


FROM alpine:latest
RUN apk add --no-cache postfix lmdb ca-certificates dumb-init tzdata

RUN addgroup -g 1001 mailpipe \
 && adduser -D -H -s /sbin/nologin -u 1001 -G mailpipe mailpipe

COPY --from=builder /app/target/release/rustpipe /usr/local/bin/rustpipe
RUN chown mailpipe:mailpipe /usr/local/bin/rustpipe && chmod 0755 /usr/local/bin/rustpipe

COPY postfix/main.cf /etc/postfix/main.cf
COPY postfix/master.cf /etc/postfix/master.cf

COPY postfix/transport /etc/postfix/transport

COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

ENTRYPOINT ["dumb-init", "--", "/entrypoint.sh"]
