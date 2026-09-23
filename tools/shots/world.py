"""Builds a made-up flare world for screenshots: two Claude logins, Codex and
OpenCode, with a believable week of use, under <root> — its own home, config,
state and data directories. Nothing here is anyone's real usage.

usage: world.py <root> <theme black|white>
Prints the pids of the placeholder processes the live sessions point at; the
caller kills them when done.
"""
import json
import os
import random
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

root = Path(sys.argv[1]).resolve()
theme = sys.argv[2] if len(sys.argv) > 2 else "black"
home, state, cfg, data = root / "home", root / "state" / "flare", root / "cfg" / "flare", root / "data"
for d in (home, state, cfg, data):
    d.mkdir(parents=True, exist_ok=True)

rng = random.Random(7)
now = int(time.time())
HOUR = 3600
DAY = 86400


def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def local_hour(t):
    return datetime.fromtimestamp(t).hour


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


# The week of the longest limit resets in a little over three days.
week_resets = now - now % HOUR + 3 * DAY + 5 * HOUR
week_start = week_resets - 7 * DAY
session_resets = now - now % 60 + 2 * HOUR + 14 * 60

# Hours of a working day, and how hard each one runs (0..1).
PROFILE = {9: .5, 10: .9, 11: 1.0, 12: .4, 14: .7, 15: .95, 16: .85, 17: .6, 18: .3, 21: .35, 22: .5, 23: .2}


def replies(login_home, projects, scale, models):
    """One jsonl per project per day, replies spread over the working hours."""
    # Every day from the week's first to today, by local midnight.
    t = int(datetime.fromtimestamp(week_start).replace(hour=12, minute=0, second=0).timestamp())
    n = 0
    while t - 12 * HOUR < now:
        day_index = (t - week_start) // DAY + 1
        weekday = datetime.fromtimestamp(t).weekday()
        for project in projects:
            lines = []
            for hour, weight in PROFILE.items():
                midnight = int(datetime.fromtimestamp(t).replace(hour=0, minute=0, second=0).timestamp())
                start = midnight + hour * HOUR
                if start >= now or start + HOUR <= week_start:
                    continue
                busy = weight * scale * (0.35 if weekday >= 5 else 1.0) * rng.uniform(.55, 1.2)
                count = int(busy * 26)
                for _ in range(count):
                    at = start + rng.randint(0, HOUR - 1)
                    if at >= now:
                        continue
                    model = rng.choices([m for m, _ in models], [w for _, w in models])[0]
                    big = 3.0 if "opus" in model else 1.0
                    usage = {
                        "input_tokens": int(rng.uniform(200, 1800) * big),
                        "output_tokens": int(rng.uniform(300, 1600) * big),
                        "cache_creation_input_tokens": int(rng.uniform(500, 6000)),
                        "cache_read_input_tokens": int(rng.uniform(18000, 70000)),
                    }
                    n += 1
                    lines.append(json.dumps({
                        "type": "assistant",
                        "timestamp": iso(at),
                        "message": {"id": f"msg_{project}_{n}", "role": "assistant", "model": model, "usage": usage},
                    }))
            if lines:
                write(login_home / "projects" / f"-home-you-code-{project}" / f"day{day_index}.jsonl", "\n".join(lines) + "\n")
        t += DAY


def capture(path, session_used, weekly_used):
    write(path, json.dumps({"rate_limits": {
        "five_hour": {"used_percentage": session_used, "resets_at": session_resets},
        "seven_day": {"used_percentage": weekly_used, "resets_at": week_resets},
    }}))
    os.utime(path, (now - 40, now - 40))


def fill_history(provider, session_used, weekly_used):
    weekly, session = [], []
    t = week_start + 6 * HOUR
    level = 0.0
    while t < now - 600:
        if local_hour(t) in PROFILE:
            level += PROFILE[local_hour(t)] * rng.uniform(.004, .011) * (0.35 if datetime.fromtimestamp(t).weekday() >= 5 else 1)
        weekly.append([t, level])
        t += HOUR
    # Scaled so the line ends where the limit stands now, with no jump.
    scale = (weekly_used / 100) / max(level, 1e-9)
    weekly = [[a, round(b * scale, 4)] for a, b in weekly] + [[now - 60, weekly_used / 100]]
    s0 = session_resets - 5 * HOUR
    for i in range(0, 5 * 12):
        at = s0 + i * 300
        if at >= now:
            break
        session.append([at, round(session_used / 100 * (i + 1) / max(1, (now - s0) // 300), 4)])
    write(state / f"history-{provider}.json", json.dumps({"weekly_all": weekly, "session": session}))


def placeholder(name):
    # Its output is not ours: left on our stdout, it would hold open the pipe
    # the caller reads the pids from, for as long as it sleeps.
    proc = subprocess.Popen(["setsid", "-f", "sleep", "7200"], stdin=subprocess.DEVNULL,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    proc.wait()
    time.sleep(0.2)
    pid = int(subprocess.check_output(["pgrep", "-n", "-x", "sleep"]).decode().strip())
    stat = Path(f"/proc/{pid}/stat").read_text()
    start = stat.rsplit(")", 1)[1].split()[19]
    return pid, start


def live_session(login_home, name, project, status, minutes, waiting_for=None):
    pid, start = placeholder(name)
    record = {
        "pid": pid, "cwd": f"/home/you/code/{project}", "name": name, "status": status,
        "startedAt": (now - minutes * 60) * 1000, "procStart": start,
    }
    if waiting_for:
        record["waitingFor"] = waiting_for
    write(login_home / "sessions" / f"{pid}.json", json.dumps(record))
    return pid


def closed_log(provider, entries):
    log = []
    for i, (name, project, ago_m, length_m) in enumerate(entries):
        start = now - ago_m * 60
        log.append({"pid": 90000 + i, "name": name, "project": project, "started_at": start,
                    "last_seen": start + length_m * 60, "state": "idle"})
    write(state / f"sessions-{provider}.json", json.dumps(log))


# ---------------- Claude, the default login ----------------
claude = home / ".claude"
write(home / ".claude.json", json.dumps({"oauthAccount": {"emailAddress": "you@example.com"}}))
replies(claude, ["atlas-api", "notes-app", "dotfiles"], 1.0,
        [("claude-sonnet-5", 58), ("claude-opus-5-5", 30), ("claude-haiku-4-5", 12)])
capture(state / "claude-statusline.json", 42, 63)
fill_history("claude", 42, 63)
pids = [
    live_session(claude, "auth-refactor", "atlas-api", "busy", 47),
    live_session(claude, "release-notes", "notes-app", "waiting", 22, "approve a command"),
    live_session(claude, "dotfiles", "dotfiles", "idle", 95),
]
closed_log("claude", [("fix-flaky-tests", "atlas-api", 330, 55), ("sync-schema", "notes-app", 250, 38),
                      ("review-pr-212", "atlas-api", 170, 70)])

# ---------------- Claude, a second login ----------------
work = home / ".claude-work"
write(work / ".credentials.json", "{}")
write(work / ".claude.json", json.dumps({"oauthAccount": {"emailAddress": "you@company.example"}}))
replies(work, ["billing-service", "infra"], 0.55, [("claude-opus-5-5", 55), ("claude-sonnet-5", 45)])
key = str(work.resolve()).strip("/").replace("/", "%")
capture(state / f"claude-statusline@{key}.json", 18, 35)
fill_history("claude:work", 18, 35)
pids.append(live_session(work, "billing-webhooks", "billing-service", "busy", 31))

# ---------------- Codex ----------------
codex = home / ".codex"
day = datetime.fromtimestamp(now)
rollout = codex / "sessions" / f"{day:%Y}" / f"{day:%m}" / f"{day:%d}" / "rollout-demo.jsonl"
lines = []
total = 0
for i in range(30):
    at = now - (30 - i) * 240
    total += rng.randint(9000, 30000)
    lines.append(json.dumps({"timestamp": iso(at), "type": "event_msg", "payload": {"type": "token_count",
        "info": {"total_token_usage": {"input_tokens": total - 900, "output_tokens": 900, "total_tokens": total}, "model_context_window": 258400},
        "rate_limits": {"limit_id": "codex", "limit_name": None,
                        "primary": {"used_percent": 27.0, "window_minutes": 10080, "resets_at": week_resets + 2 * DAY},
                        "secondary": {"used_percent": 71.0, "window_minutes": 300, "resets_at": session_resets - HOUR},
                        "plan_type": "plus"}}}))
write(rollout, "\n".join(lines) + "\n")
os.utime(rollout, (now - 60, now - 60))

# ---------------- OpenCode ----------------
db_path = data / "opencode" / "opencode.db"
db_path.parent.mkdir(parents=True, exist_ok=True)
if db_path.exists():
    db_path.unlink()
db = sqlite3.connect(db_path)
db.executescript("""
CREATE TABLE session (id text PRIMARY KEY, parent_id text, title text NOT NULL, directory text NOT NULL,
  time_created integer NOT NULL, time_updated integer NOT NULL, cost real DEFAULT 0 NOT NULL,
  tokens_input integer DEFAULT 0 NOT NULL, tokens_output integer DEFAULT 0 NOT NULL,
  tokens_reasoning integer DEFAULT 0 NOT NULL, tokens_cache_read integer DEFAULT 0 NOT NULL,
  tokens_cache_write integer DEFAULT 0 NOT NULL);
CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, data text NOT NULL);
""")
for s, (title, project, hours_ago, length) in enumerate([("port the parser", "atlas-api", 5, 2), ("benchmarks", "notes-app", 26, 3), ("ci cache", "infra", 50, 1)]):
    start = now - hours_ago * HOUR
    tin = tout = tread = 0
    for m in range(length * 20):
        at = start + m * 170
        i, o, r = rng.randint(800, 4000), rng.randint(300, 1500), rng.randint(9000, 40000)
        tin, tout, tread = tin + i, tout + o, tread + r
        db.execute("INSERT INTO message VALUES (?,?,?,?)", (f"m{s}-{m}", f"s{s}", at * 1000, json.dumps(
            {"role": "assistant", "modelID": rng.choice(["qwen3-coder", "kimi-k2", "glm-4.6"]),
             "tokens": {"input": i, "output": o, "cache": {"read": r, "write": 0}}})))
    db.execute("INSERT INTO session VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
               (f"s{s}", None, title, f"/home/you/code/{project}", start * 1000, (start + length * HOUR) * 1000,
                round(rng.uniform(.4, 2.5), 2), tin, tout, 0, tread, 0))
db.commit()

# ---------------- flare's own config ----------------
write(cfg / "config.toml", f"""[data]
mode = "local"
[ui]
language = "en"
[theme]
mode = "{theme}"
ring_color = "provider"
[notch]
label = "percent"
[sessions]
show = true
[notify]
waiting = false
limit = false
reset = false
[providers]
cursor = false
antigravity = false
kiro = false
order = ["claude", "claude:work", "codex", "opencode"]
[scan]
window_days = 1
""")
print(" ".join(str(p) for p in pids))
