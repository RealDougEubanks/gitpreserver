#!/usr/bin/env python3
"""
GitPreserver web UI — stdlib only, no pip dependencies.

Routes:
  GET  /         Status dashboard (HTML)
  GET  /healthz  Liveness/readiness check (JSON)
  GET  /config   Active configuration with secrets redacted (JSON)
  POST /run      Trigger an immediate backup run
"""

import hmac
import http.server
import json
import os
import secrets
import subprocess
import sys
import threading
from datetime import datetime, timezone
from urllib.parse import urlsplit

# Component name for structured log lines emitted by this process.
_LOG_COMPONENT = "webserver"
# Correlation id, stable for the life of the process. Reuse one threaded in from
# a parent (the daemon exports GITPRESERVER_RUN_ID); otherwise derive a cheap
# per-process id matching the bash helper's date-PID shape.
_RUN_ID = os.environ.get("GITPRESERVER_RUN_ID") or "{0}-{1}".format(
    datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"), os.getpid()
)


def _log_escape(value):
    """Escape a value for a double-quoted logfmt field: backslashes and quotes
    are escaped and newlines/tabs folded to spaces so a message can never inject
    extra fields or spill onto fake log lines."""
    s = str(value)
    s = s.replace("\\", "\\\\").replace('"', '\\"')
    s = s.replace("\n", " ").replace("\r", " ").replace("\t", " ")
    return s


def log(level, msg):
    """Emit one logfmt record to stderr matching backup/lib/log.sh."""
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    print(
        'ts={0} level={1} component={2} run_id={3} msg="{4}"'.format(
            ts, level, _LOG_COMPONENT, _RUN_ID, _log_escape(msg)
        ),
        file=sys.stderr, flush=True,
    )

PORT = int(os.environ.get("GITPRESERVER_WEB_PORT", "6033"))
BIND = os.environ.get("GITPRESERVER_WEB_BIND", "0.0.0.0")
STATUS_FILE = os.environ.get("GITPRESERVER_STATUS_FILE", "/tmp/gitpreserver-status.json")
LOCK_FILE = "/tmp/gitpreserver.lock"
_REDACT = {"TOKEN", "PASS", "KEY", "SECRET", "PASSWORD", "ACCOUNT"}
# Keys whose values are URLs containing embedded credentials (webhooks, etc.).
_REDACT_URL = {"WEBHOOK", "URL"}
# Reject POST bodies larger than this (bytes). Mutating routes take no payload.
MAX_BODY_BYTES = 4096


def _load_token():
    """Return the bearer token guarding mutating/sensitive routes.

    Read from GITPRESERVER_WEB_TOKEN; if unset, generate a random one at
    startup and print it to stderr so the operator can find it.
    """
    token = os.environ.get("GITPRESERVER_WEB_TOKEN", "").strip()
    if token:
        return token
    token = secrets.token_urlsafe(32)
    log("warn", "GITPRESERVER_WEB_TOKEN not set; generated a random web token "
                "for POST /run and GET /config")
    log("warn", f"generated web token: {token}")
    return token


WEB_TOKEN = _load_token()


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_status():
    try:
        with open(STATUS_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"status": "unknown", "last_run": None, "message": "No backup has run yet."}


def write_status(data):
    try:
        with open(STATUS_FILE, "w") as f:
            json.dump(data, f)
    except OSError as exc:
        log("error", f"failed to write status file {STATUS_FILE}: {exc}")


def _redact_url(value):
    """Show only scheme+host of a URL; hide path/query/credentials."""
    try:
        parts = urlsplit(value)
    except ValueError:
        return "[redacted]"
    if parts.scheme and parts.hostname:
        return f"{parts.scheme}://{parts.hostname}/…[redacted]"
    return "[redacted]"


def get_config():
    result = {}
    for k, v in sorted(os.environ.items()):
        if k.startswith(("GITPRESERVER_", "RCLONE_CONFIG_")):
            ku = k.upper()
            if not v:
                result[k] = v
            elif any(s in ku for s in _REDACT):
                result[k] = "***"
            elif any(s in ku for s in _REDACT_URL):
                result[k] = _redact_url(v)
            else:
                result[k] = v
    return result


def trigger_backup():
    status = read_status()
    if status.get("status") == "running":
        return
    write_status({"status": "running", "last_run": now_iso(),
                  "message": "Manually triggered via web UI."})
    try:
        result = subprocess.run(
            ["flock", "-n", LOCK_FILE, "run-stages.sh"],
            capture_output=True, text=True
        )
        # The stage scripts already emit structured logfmt lines on their own
        # streams; relay them verbatim rather than re-wrapping them in a msg=.
        output = (result.stdout + result.stderr).strip()
        if output:
            print(output, file=sys.stderr, flush=True)
        if result.returncode == 1 and not output:
            write_status({"status": "skipped", "last_run": now_iso(),
                          "message": "A backup is already running."})
        else:
            write_status({
                "status": "success" if result.returncode == 0 else "failed",
                "last_run": now_iso(),
                "message": output[-3000:],
            })
    except Exception as exc:
        log("error", f"backup trigger failed: {exc}")
        write_status({"status": "error", "last_run": now_iso(), "message": str(exc)})


def _esc(text):
    return (str(text)
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;"))


def render_dashboard():
    status = read_status()
    config = get_config()

    badge_colors = {
        "success": "#22c55e",
        "failed":  "#ef4444",
        "running": "#f59e0b",
        "skipped": "#6b7280",
        "error":   "#ef4444",
        "idle":    "#3b82f6",
        "unknown": "#6b7280",
    }
    state = status.get("status", "unknown")
    badge_color = badge_colors.get(state, "#6b7280")
    is_running = state == "running"
    btn_disabled = 'disabled style="opacity:.5;cursor:not-allowed"' if is_running else ""

    config_rows = "".join(
        f"<tr><td>{_esc(k)}</td><td>{_esc(v)}</td></tr>"
        for k, v in config.items()
    )
    message = _esc(status.get("message") or "")
    message_block = f'<pre>{message}</pre>' if message else ""

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>GitPreserver</title>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
{_refresh_meta(is_running)}
<style>
*{{box-sizing:border-box;margin:0;padding:0}}
body{{font-family:system-ui,sans-serif;background:#0f172a;color:#e2e8f0;min-height:100vh}}
.topbar{{background:#1e293b;padding:1rem 2rem;display:flex;align-items:center;gap:.75rem;border-bottom:1px solid #334155}}
.topbar h1{{font-size:1.1rem;font-weight:600;color:#f1f5f9}}
.topbar .sub{{font-size:.75rem;color:#64748b;margin-top:2px}}
main{{max-width:860px;margin:2rem auto;padding:0 1.25rem;display:grid;gap:1.25rem}}
.card{{background:#1e293b;border:1px solid #334155;border-radius:8px;padding:1.25rem}}
.card h2{{font-size:.75rem;font-weight:600;text-transform:uppercase;letter-spacing:.06em;color:#64748b;margin-bottom:.875rem}}
.badge{{display:inline-block;padding:.25rem .75rem;border-radius:9999px;font-size:.8rem;font-weight:700;color:#fff;background:{badge_color}}}
.meta{{color:#64748b;font-size:.8rem;margin-top:.4rem}}
.btn{{background:#ff6a00;color:#fff;border:none;padding:.45rem 1.1rem;border-radius:6px;font-size:.8rem;font-weight:600;cursor:pointer;margin-top:.875rem}}
.btn:hover:not([disabled]){{background:#e05f00}}
pre{{background:#0f172a;border-radius:4px;padding:.875rem;font-size:.72rem;line-height:1.5;overflow:auto;white-space:pre-wrap;color:#94a3b8;max-height:220px;margin-top:.875rem;border:1px solid #334155}}
table{{width:100%;border-collapse:collapse;font-size:.78rem}}
td{{padding:.35rem .5rem;border-bottom:1px solid #1e293b;vertical-align:top;word-break:break-all}}
tr:last-child td{{border-bottom:none}}
td:first-child{{color:#64748b;width:45%;padding-right:1rem}}
.dot{{width:8px;height:8px;border-radius:50%;background:{badge_color};display:inline-block;margin-right:6px}}
</style>
</head>
<body>
<div class="topbar">
  <div>
    <h1><span class="dot"></span>GitPreserver</h1>
    <div class="sub">Backup monitoring dashboard</div>
  </div>
</div>
<main>
  <div class="card">
    <h2>Status</h2>
    <span class="badge">{_esc(state.upper())}</span>
    <div class="meta">Last run: {_esc(status.get('last_run') or 'Never')}</div>
    <div class="meta">Schedule: {_esc(status.get('schedule') or os.environ.get('GITPRESERVER_SCHEDULE','0 2 * * 0'))}</div>
    {message_block}
    <button class="btn" onclick="triggerRun()" {btn_disabled}>&#9654; Run Now</button>
  </div>
  <div class="card">
    <h2>Configuration</h2>
    <table>{config_rows if config_rows else '<tr><td colspan=2 style="color:#64748b">No GITPRESERVER_* or RCLONE_CONFIG_* variables set.</td></tr>'}</table>
  </div>
</main>
<script>
function triggerRun(){{
  var t=window.prompt('Enter web token (GITPRESERVER_WEB_TOKEN):');
  if(!t) return;
  fetch('/run',{{method:'POST',headers:{{'Authorization':'Bearer '+t,'Content-Length':'0'}}}})
    .then(function(r){{if(!r.ok)alert('Run failed: '+r.status);setTimeout(function(){{location.reload();}},800);}})
    .catch(console.error);
}}
</script>
</body>
</html>"""


def _refresh_meta(is_running):
    return '<meta http-equiv="refresh" content="5"/>' if is_running else ""


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # suppress per-request access log; errors still print

    def send_json(self, data, code=200):
        body = json.dumps(data, indent=2).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_html(self, html, code=200):
        body = html.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _is_authorized(self):
        """Constant-time bearer-token check on the Authorization header."""
        header = self.headers.get("Authorization", "")
        prefix = "Bearer "
        if not header.startswith(prefix):
            return False
        return hmac.compare_digest(header[len(prefix):], WEB_TOKEN)

    def _origin_matches_host(self):
        """Reject cross-origin POSTs: if Origin is present its host must match Host."""
        origin = self.headers.get("Origin")
        if not origin:
            return True  # no Origin header (e.g. curl) — token auth still applies
        host = self.headers.get("Host", "")
        try:
            origin_host = urlsplit(origin).netloc
        except ValueError:
            return False
        return bool(origin_host) and origin_host == host

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/healthz":
            status = read_status()
            ok = status.get("status") in ("success", "idle", "unknown", "skipped")
            self.send_json({
                "status": "ok" if ok else "degraded",
                "last_run": status.get("last_run"),
                "last_result": status.get("status"),
                "schedule": status.get("schedule",
                            os.environ.get("GITPRESERVER_SCHEDULE", "0 2 * * 0")),
            }, code=200 if ok else 503)
        elif path == "/config":
            if not self._is_authorized():
                self.send_json({"error": "unauthorized"}, 401)
                return
            self.send_json(get_config())
        elif path in ("/", "/status"):
            self.send_html(render_dashboard())
        else:
            self.send_json({"error": "not found"}, 404)

    def _drain_body(self):
        """Read and discard any request body so the connection stays usable."""
        try:
            length = int(self.headers.get("Content-Length", "0") or "0")
        except ValueError:
            length = 0
        if length > 0:
            try:
                self.rfile.read(length)
            except OSError:
                pass

    def do_POST(self):
        path = self.path.split("?")[0]
        if path != "/run":
            self.send_json({"error": "not found"}, 404)
            return

        # Bound the request body: a manual trigger carries no payload.
        raw_len = self.headers.get("Content-Length")
        if raw_len is None:
            self.send_json({"error": "Content-Length required"}, 411)
            return
        try:
            content_length = int(raw_len)
        except ValueError:
            self.send_json({"error": "invalid Content-Length"}, 400)
            return
        if content_length < 0 or content_length > MAX_BODY_BYTES:
            self.send_json({"error": "payload too large"}, 413)
            return

        self._drain_body()

        # CSRF defense: reject cross-origin POSTs.
        if not self._origin_matches_host():
            self.send_json({"error": "origin not allowed"}, 403)
            return

        # Bearer-token authentication.
        if not self._is_authorized():
            self.send_json({"error": "unauthorized"}, 401)
            return

        threading.Thread(target=trigger_backup, daemon=True).start()
        self.send_json({"status": "started"})


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer((BIND, PORT), Handler)
    log("info", f"Web UI listening on {BIND}:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
