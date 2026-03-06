# rustpipe

`rustpipe` is a rudimentary proof of concept for Postfix handoff handling.

## Why Rust Here

- Fast startup and low runtime overhead for Postfix pipe execution.
- Strong memory and type safety for parsing untrusted email input.
- Good throughput and predictable latency for a hot ingress path.
- Small deployable binary, well-suited for containers.

## Purpose

- Accept inbound message data from Postfix.
- Perform minimal validation/parsing.
- Hand off quickly to a downstream processing service.

## Postfix Argument Map

`rustpipe` receives these fields from the Postfix pipe service argv:

| Group | Arg | Meaning |
| --- | --- | --- |
| Envelope | `recipient` | SMTP envelope recipient (`RCPT TO`) |
| Envelope | `sender` | SMTP envelope sender (`MAIL FROM`) |
| Client | `client_address` | Remote client IP |
| Client | `client_hostname` | Remote hostname (if resolved) |
| Client | `client_helo` | HELO/EHLO value provided by client |
| Client | `client_port` | Remote TCP source port |
| Client | `client_protocol` | Postfix client protocol/session label |
| SASL | `sasl_username` | Authenticated SMTP username (if present) |
| SASL | `sasl_method` | SASL method (for example `PLAIN`, `LOGIN`) |
| SASL | `sasl_sender` | Sender identity associated with SASL auth |
| Queue | `queue_id` | Postfix queue identifier for the message |
| Queue | `size` | Message size in bytes |
| Recipient parts | `original_recipient` | Recipient before aliasing/rewrites |
| Recipient parts | `domain` | Recipient domain part |
| Recipient parts | `mailbox` | Recipient local part (may include extension) |
| Recipient parts | `extension` | Recipient extension after delimiter (`+`) |
| Recipient parts | `nexthop` | Transport next-hop chosen by Postfix |
| Recipient parts | `user` | Base local user portion |

Notes:

- Most args are optional in code and default to empty values for local testing.
- If envelope values are missing, `rustpipe` falls back to message headers.

## What This Is Not

- Not a full message processing engine.
- Not intended to write directly to a database.
- Not intended to own complex retry, routing, or business logic.

## Error Handling Model

For production systems, defer durable delivery retry behavior to Postfix
itself. `rustpipe` should signal outcome via exit codes and let Postfix queue
and retry scheduling handle redelivery.

Transient failures should prefer Postfix retry behavior:

- `Outcome::Retry(msg)` returns `EX_TEMPFAIL` (`75`).
- Postfix keeps the message in its queue and retries delivery on its normal
  schedule.
- This is usually better than implementing retry loops inside `rustpipe`.
- Operational error reporting/alerting should be handled by the downstream
  processing service, not by `rustpipe`.

Queue persistence behavior:

- Undelivered queued mail survives Postfix process restarts.
- In this compose setup, `/var/spool/postfix` is bind-mounted to
  `./postfix/spool`, which Docker creates automatically and reuses
  across container recreations.

## Performance Notes

- The current implementation is acceptable for small workloads.
- At higher load, this direct model will become a bottleneck.
- File-based tracing at `info` level does not scale well because of high
  read/write pressure on log files.

## Recommended Direction

Keep `rustpipe` fast and lightweight. Use it as an ingress shim, and move
heavy processing, persistence, and resilience logic to a downstream
processing service.
