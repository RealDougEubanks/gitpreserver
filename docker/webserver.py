#!/usr/bin/env python3
"""
GitPreserver web UI — stdlib only, no pip dependencies.

Routes:
  GET  /         Status dashboard (HTML)
  GET  /healthz  Liveness/readiness check (JSON)
  GET  /config   Active configuration with secrets redacted (JSON)
  POST /run      Trigger an immediate backup run
"""

import http.server
import json
import os
import subprocess
import sys
import threading
from datetime import datetime, timezone

PORT = int(os.environ.get("GITPRESERVER_WEB_PORT", "6033"))
STATUS_FILE = os.environ.get("GITPRESERVER_STATUS_FILE", "/tmp/gitpreserver-status.json")
LOCK_FILE = "/tmp/gitpreserver.lock"
_REDACT = {"TOKEN", "PASS", "KEY", "SECRET", "PASSWORD", "ACCOUNT"}


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
    except OSError:
        pass


def get_config():
    result = {}
    for k, v in sorted(os.environ.items()):
        if k.startswith(("GITPRESERVER_", "RCLONE_CONFIG_")):
            redact = any(s in k.upper() for s in _REDACT)
            result[k] = "***" if (redact and v) else v
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
        output = (result.stdout + result.stderr).strip()
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
  fetch('/run',{{method:'POST'}})
    .then(()=>setTimeout(()=>location.reload(),800))
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
            self.send_json(get_config())
        elif path in ("/", "/status"):
            self.send_html(render_dashboard())
        else:
            self.send_json({"error": "not found"}, 404)

    def do_POST(self):
        path = self.path.split("?")[0]
        if path == "/run":
            threading.Thread(target=trigger_backup, daemon=True).start()
            self.send_json({"status": "started"})
        else:
            self.send_json({"error": "not found"}, 404)


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"[gitpreserver] Web UI listening on port {PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
