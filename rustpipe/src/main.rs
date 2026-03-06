use anyhow::Result;
use clap::Parser;
use mailparse::MailHeaderMap;
use std::{
    fs::OpenOptions,
    io::{self, Read},
    process,
};
use tracing::{error, info};
use tracing_subscriber::EnvFilter;

const LOG_PATH: &str = "/var/log/rustpipe.log";

#[derive(Parser, Debug)]
struct Args {
    // Envelope
    #[arg(long, default_value = "")] recipient: String,
    #[arg(long, default_value = "")] sender: String,

    // Client
    #[arg(long, default_value = "")] client_address: String,
    #[arg(long, default_value = "")] client_hostname: String,
    #[arg(long, default_value = "")] client_helo: String,
    #[arg(long, default_value = "")] client_port: String,
    #[arg(long, default_value = "")] client_protocol: String,

    // SASL
    #[arg(long, default_value = "")] sasl_username: String,
    #[arg(long, default_value = "")] sasl_method: String,
    #[arg(long, default_value = "")] sasl_sender: String,

    // Queue
    #[arg(long, default_value = "")] queue_id: String,
    #[arg(long, default_value = "0")] size: u64,

    // Recipient parts
    #[arg(long, default_value = "")] original_recipient: String,
    #[arg(long, default_value = "")] domain: String,
    #[arg(long, default_value = "")] mailbox: String,
    #[arg(long, default_value = "")] extension: String,
    #[arg(long, default_value = "")] nexthop: String,
    #[arg(long, default_value = "")] user: String,
}

enum Outcome {
    Accepted,
    Retry(String),  // EX_TEMPFAIL -> requeue
    Bounce(String), // EX_UNAVAILABLE -> bounce
}

fn exit_with(outcome: Outcome) -> ! {
    match outcome {
        Outcome::Accepted => process::exit(0),
        Outcome::Retry(msg) => {
            eprintln!("{msg}");
            process::exit(75);
        }
        Outcome::Bounce(msg) => {
            eprintln!("{msg}");
            process::exit(69);
        }
    }
}

fn init_tracing() {
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("warn"));

    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(LOG_PATH)
        .unwrap_or_else(|e| panic!("cannot open {} for append: {}", LOG_PATH, e));

    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_writer(file)
        .with_ansi(false)
        .compact()
        .init(); // fail loud
}

fn main() -> Result<()> {
    init_tracing();

    let args = Args::parse();

    let mut raw = Vec::new();
    io::stdin().read_to_end(&mut raw)?;

    let parsed = match mailparse::parse_mail(&raw) {
        Ok(p) => p,
        Err(e) => {
            error!(error = %e, bytes = raw.len(), "parse failed");
            exit_with(Outcome::Bounce("invalid message format".to_string()));
        }
    };

    let subject  = parsed.headers.get_first_value("Subject").unwrap_or_default();
    let from_hdr = parsed.headers.get_first_value("From").unwrap_or_default();
    let to_hdr   = parsed.headers.get_first_value("To").unwrap_or_default();
    let date_hdr = parsed.headers.get_first_value("Date").unwrap_or_default();

    let sender = if args.sender.is_empty() { &from_hdr } else { &args.sender };
    let recipient = if args.recipient.is_empty() { &to_hdr } else { &args.recipient };

    info!(
        recipient = %recipient,
        sender = %sender,

        client_address = %args.client_address,
        client_hostname = %args.client_hostname,
        client_helo = %args.client_helo,
        client_port = %args.client_port,
        client_protocol = %args.client_protocol,

        sasl_username = %args.sasl_username,
        sasl_method = %args.sasl_method,
        sasl_sender = %args.sasl_sender,

        queue_id = %args.queue_id,
        size = args.size,

        original_recipient = %args.original_recipient,
        domain = %args.domain,
        mailbox = %args.mailbox,
        extension = %args.extension,
        nexthop = %args.nexthop,
        user = %args.user,

        subject = %subject,
        from_hdr = %from_hdr,
        to_hdr = %to_hdr,
        date = %date_hdr,

        bytes = raw.len(),
        "mail received"
    );

    exit_with(Outcome::Accepted);
}
