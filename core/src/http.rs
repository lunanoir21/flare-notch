//! The one place flare opens a network connection. Only official mode calls it.
//!
//! Errors never carry request headers, so a bearer token cannot end up in a
//! note, a log line or the widget.

use std::fmt;
use std::io::Read;
use std::time::Duration;

use serde_json::Value;

/// A usage endpoint replies with a small JSON document; this is generous
/// headroom over that, not a real expectation. Reading is capped here
/// instead of trusting the endpoint (or a MITM, since nothing pins the
/// certificate) to keep its reply short.
const MAX_BODY_BYTES: u64 = 4 * 1024 * 1024;

#[derive(Debug)]
pub enum HttpError {
    Status { code: u16, retry_after: Option<u64> },
    Transport(String),
    Parse(String),
}

impl fmt::Display for HttpError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Status { code, .. } => write!(f, "HTTP {code}"),
            Self::Transport(message) => write!(f, "{message}"),
            Self::Parse(message) => write!(f, "unreadable reply: {message}"),
        }
    }
}

/// GET a JSON document, with a 15 second timeout.
pub fn get_json(url: &str, headers: &[(&str, &str)]) -> Result<Value, HttpError> {
    let agent = ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(15))
        .user_agent(concat!("flare/", env!("CARGO_PKG_VERSION"), " (Linux)"))
        .build();
    let mut request = agent.get(url);
    for (name, value) in headers {
        request = request.set(name, value);
    }
    match request.call() {
        Ok(response) => {
            let mut body = Vec::new();
            // One byte past the cap, so a reply that lands exactly on it and
            // one that overflows it are told apart without reading further.
            response
                .into_reader()
                .take(MAX_BODY_BYTES + 1)
                .read_to_end(&mut body)
                .map_err(|err| HttpError::Transport(err.to_string()))?;
            if body.len() as u64 > MAX_BODY_BYTES {
                return Err(HttpError::Transport(format!("reply larger than {MAX_BODY_BYTES} bytes")));
            }
            serde_json::from_slice(&body).map_err(|err| HttpError::Parse(err.to_string()))
        }
        Err(ureq::Error::Status(code, response)) => {
            let retry_after = response
                .header("retry-after")
                .and_then(|value| value.trim().parse().ok());
            Err(HttpError::Status { code, retry_after })
        }
        Err(err) => Err(HttpError::Transport(err.kind().to_string())),
    }
}
