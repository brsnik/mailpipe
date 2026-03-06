#!/bin/sh
set -eu

: "${MAIL_DOMAIN:?MAIL_DOMAIN is required}"
: "${MAIL_HOSTNAME:?MAIL_HOSTNAME is required}"
: "${INET_INTERFACES:?INET_INTERFACES is required}"
: "${INET_PROTOCOLS:?INET_PROTOCOLS is required}"
: "${DEBUG_PEER_LIST:?DEBUG_PEER_LIST is required}"
: "${DEBUG_PEER_LEVEL:?DEBUG_PEER_LEVEL is required}"
: "${RELAY_ALLOWLIST:?RELAY_ALLOWLIST is required}"

# Optional TLS settings (required only when TLS is enabled in main.cf).
SMTPD_TLS_LOGLEVEL="${SMTPD_TLS_LOGLEVEL:-}"
SMTPD_TLS_SECURITY_LEVEL="${SMTPD_TLS_SECURITY_LEVEL:-none}"
SMTPD_TLS_CERT_FILE="${SMTPD_TLS_CERT_FILE:-}"
SMTPD_TLS_KEY_FILE="${SMTPD_TLS_KEY_FILE:-}"

if [ "${SMTPD_TLS_SECURITY_LEVEL}" != "none" ]; then
  : "${SMTPD_TLS_LOGLEVEL:?SMTPD_TLS_LOGLEVEL is required when SMTPD_TLS_SECURITY_LEVEL is not none}"
  : "${SMTPD_TLS_CERT_FILE:?SMTPD_TLS_CERT_FILE is required when SMTPD_TLS_SECURITY_LEVEL is not none}"
  : "${SMTPD_TLS_KEY_FILE:?SMTPD_TLS_KEY_FILE is required when SMTPD_TLS_SECURITY_LEVEL is not none}"

  test -r "${SMTPD_TLS_CERT_FILE}" || {
    echo "TLS certificate file not readable: ${SMTPD_TLS_CERT_FILE}" >&2
    exit 1
  }
  test -r "${SMTPD_TLS_KEY_FILE}" || {
    echo "TLS private key file not readable: ${SMTPD_TLS_KEY_FILE}" >&2
    exit 1
  }
else
  # Safe placeholders for commented/disabled TLS directives.
  SMTPD_TLS_CERT_FILE="/dev/null"
  SMTPD_TLS_KEY_FILE="/dev/null"
fi

# Inject env into main.cf
sed -i \
  -e "s/\${MAIL_DOMAIN}/${MAIL_DOMAIN}/g" \
  -e "s/\${MAIL_HOSTNAME}/${MAIL_HOSTNAME}/g" \
  -e "s/\${INET_INTERFACES}/${INET_INTERFACES}/g" \
  -e "s/\${INET_PROTOCOLS}/${INET_PROTOCOLS}/g" \
  -e "s|\${RELAY_ALLOWLIST}|${RELAY_ALLOWLIST}|g" \
  -e "s|\${DEBUG_PEER_LIST}|${DEBUG_PEER_LIST}|g" \
  -e "s/\${DEBUG_PEER_LEVEL}/${DEBUG_PEER_LEVEL}/g" \
  -e "s/\${SMTPD_TLS_LOGLEVEL}/${SMTPD_TLS_LOGLEVEL}/g" \
  -e "s|\${SMTPD_TLS_SECURITY_LEVEL}|${SMTPD_TLS_SECURITY_LEVEL}|g" \
  -e "s|\${SMTPD_TLS_CERT_FILE}|${SMTPD_TLS_CERT_FILE}|g" \
  -e "s|\${SMTPD_TLS_KEY_FILE}|${SMTPD_TLS_KEY_FILE}|g" \
  /etc/postfix/main.cf

# Ensure postfix has a non-empty hostname before postmap reads main.cf
postconf -e "myhostname = ${MAIL_HOSTNAME}"

# Ensure rust log file exists and is readable on host bind-mount
mkdir -p /var/log
touch /var/log/rustpipe.log
chown mailpipe:mailpipe /var/log/rustpipe.log
chmod 0644 /var/log/rustpipe.log

# Compile transport map (expects /etc/postfix/transport to be mounted/copied already)
test -s /etc/postfix/transport
postmap /etc/postfix/transport

# Keep Postfix in the foreground so the container PID 1 stays alive.
exec postfix -c /etc/postfix start-fg
