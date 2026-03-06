# mailpipe (PoC)

`mailpipe` is a lightweight Alpine container bundling Postfix with a Rust handler (`rustpipe`).
Postfix accepts inbound SMTP and pipes each accepted message to `rustpipe` for processing.

## Why

This is useful when you want to reduce dependency/cost on third-party inbound processing services (for example, SendGrid or Mailgun inbound routes, or AWS SES + Lambda pipelines) and keep message handling logic in your own stack.

You can run this in two modes:
- Upstream-forwarded mode: your primary mail platform (for example, Microsoft 365, Google Workspace, or another provider) receives mail first and forwards only selected recipients to this server.
- Direct-delivery mode: sender mail servers deliver directly to this server for the domain/subdomain you expose here (no upstream forwarding rules).

Running your own outbound mail delivery is usually a bad tradeoff for most teams (deliverability, reputation, and abuse handling), so this project is intentionally inbound-only.
Outbound SMTP delivery is disabled by default.

## Setup

### 1. DNS

- Create `MX` for `pipe.domain.tld` -> `inbound.pipe.domain.tld`
- Create `A`/`AAAA` for `inbound.pipe.domain.tld` -> your public SMTP IP
- Ensure reverse DNS `PTR` is configured for the SMTP IP

### 2. Network and firewall

- Allow inbound `TCP/25` only from trusted sender networks
- Deny inbound `TCP/25` from all other sources
- Deny outbound `TCP/25` as a guardrail

### 3. Container configuration

Required environment variables:

- `MAIL_DOMAIN` (example: `pipe.domain.tld`)
- `MAIL_HOSTNAME` (example: `inbound.pipe.domain.tld`)
- `INET_INTERFACES`
- `INET_PROTOCOLS`
- `RELAY_ALLOWLIST` (trusted CIDRs only; never `0.0.0.0/0` in production)
- `DEBUG_PEER_LIST`
- `DEBUG_PEER_LEVEL`

Optional TLS env vars (required only when `SMTPD_TLS_SECURITY_LEVEL` is not `none`):

- `SMTPD_TLS_SECURITY_LEVEL` (for example: `encrypt`)
- `SMTPD_TLS_LOGLEVEL`
- `SMTPD_TLS_CERT_FILE`
- `SMTPD_TLS_KEY_FILE`


### 4. Postfix behavior (current defaults)

- Identity/scope:
  - `myhostname = ${MAIL_HOSTNAME}`
  - `mydomain = ${MAIL_DOMAIN}`
  - `recipient_delimiter = +` (plus-addressing support)
  - `mydestination` controls which local domains are accepted.
- Network posture:
  - `mynetworks = ${RELAY_ALLOWLIST}` (set this to trusted CIDRs only).
  - TLS/access hardening directives are present as a template in `main.cf` and can be uncommented when you want strict enforcement.
- Routing:
  - `default_database_type = lmdb`
  - `transport_maps = lmdb:/etc/postfix/transport`
  - `postfix/transport` is compiled at container start via `postmap`.
- Inbound-only enforcement:
  - `default_transport = error:outbound_delivery_disabled`
  - `relay_transport = error:outbound_delivery_disabled`
- Operations:
  - `maillog_file = /dev/stdout` (container-friendly logging)
  - `anvil_rate_time_unit = 60s`
  - `debug_peer_*` and `smtpd_tls_loglevel` are controlled by env vars.

### 5. Forward from Microsoft 365

1. Create a mail contact in Exchange Online for external target `support@pipe.domain.tld`
2. Create a mail flow rule:
   - Condition: recipient is `inbound@pipe.domain.tld`
   - Action: redirect message to the mail contact above
   - Enable `Stop processing more rules`
3. Optional hardening: use an outbound connector scoped to this flow with enforced TLS/certificate validation
4. Send a test message and verify Postfix logs + `rustpipe` log

## Local testing

Build image and start container
```bash
docker compose build
docker compose up -d
```

### Allowed recipient
```bash
docker exec mailpipe sh -lc '
printf "%s\n" \
  "From: sender@pipe.domain.tld" \
  "To: support+demo@pipe.domain.tld" \
  "Subject: allowed-test" \
  "" \
  "hello" \
| sendmail -i -f sender@pipe.domain.tld support+demo@pipe.domain.tld'
```

### Denied recipient
```bash
docker exec mailpipe sh -lc '
printf "%s\n" \
  "From: sender@pipe.domain.tld" \
  "To: noone@pipe.domain.tld" \
  "Subject: denied-test" \
  "" \
  "hello" \
| sendmail -i -f sender@pipe.domain.tld noone@pipe.domain.tld'
```
