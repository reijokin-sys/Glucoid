#!/usr/bin/env python3
"""A fake Nightscout server for testing Glucoid without a real sensor.

Run it:

    python3 tests/fake-nightscout.py            # listens on 127.0.0.1:18081

The answer depends on the current mode, which is read from the file given by
GLUCOID_FAKE_MODE_FILE (default /tmp/glucoid-fake-mode, missing = "two"), so
the mode can be changed while the widget is running:

    echo single > /tmp/glucoid-fake-mode

Modes:

    two        two readings, newest first (sgv 185 at the current time,
               previous 175 five minutes earlier)
    ascending  the same two readings oldest first - the widget must still
               treat the newer one as the latest
    single     one reading (sgv 150) with direction FortyFiveDown, so the
               arrow has to come from the API field
    empty      an empty JSON array
    garbage    JSON that is not a list
    http500    HTTP 500
    old        the newest reading is 30 minutes old (tests the stale limit)
    secret403  HTTP 403 when the query carries api_secret= and 200 with
               token=, which is what happens when the user picked the wrong
               credential style (the widget retries automatically)

See docs/PLASMOIDI.md ("Testaus valepalvelinta vasten") for the whole
procedure, including how to point a copy of the widget at this server.
"""

import http.server
import json
import os
import time

DEFAULT_MODE_FILE = "/tmp/glucoid-fake-mode"
PORT = 18081


def current_mode():
    path = os.environ.get("GLUCOID_FAKE_MODE_FILE", DEFAULT_MODE_FILE)
    if os.path.exists(path):
        with open(path, encoding="utf-8") as handle:
            return handle.read().strip() or "two"
    return "two"


def readings(mode):
    now = int(time.time() * 1000)
    newest = now - (30 * 60 * 1000 if mode == "old" else 0)
    two = [{"sgv": 185, "date": newest, "direction": "Flat"},
           {"sgv": 175, "date": newest - 300000, "direction": "Flat"}]
    if mode == "ascending":
        return list(reversed(two))
    if mode == "single":
        return [{"sgv": 150, "date": newest, "direction": "FortyFiveDown"}]
    return two


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802 (name required by http.server)
        mode = current_mode()

        if mode == "secret403" and "api_secret=" in self.path:
            self.send_response(403)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if mode == "http500":
            self.send_response(500)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        if mode == "empty":
            body = b"[]"
        elif mode == "garbage":
            body = b'{"status":200,"result":"not a list"}'
        else:
            body = json.dumps(readings(mode)).encode()

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass  # keep the test output quiet


if __name__ == "__main__":
    print(f"fake Nightscout on http://127.0.0.1:{PORT} (mode file: "
          f"{os.environ.get('GLUCOID_FAKE_MODE_FILE', DEFAULT_MODE_FILE)})")
    http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
