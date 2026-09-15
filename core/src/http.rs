//! The one place flare opens a network connection. Only official mode calls it.
//!
//! Errors never carry request headers, so a bearer token cannot end up in a
//! note, a log line or the widget.

use std::fmt;
use std::time::Duration;

use serde_json::Value;

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
            let text = response
                .into_string()
                .map_err(|err| HttpError::Transport(err.to_string()))?;
            serde_json::from_str(&text).map_err(|err| HttpError::Parse(err.to_string()))
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
