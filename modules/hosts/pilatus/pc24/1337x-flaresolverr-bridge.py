import json
import os
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, HTTPServer, ThreadingHTTPServer

BROWSERLESS_ENDPOINT = "https://production-sfo.browserless.io/unblock"
FLARESOLVERR_URL = "http://127.0.0.1:8191/v1"
KERNEL_ENDPOINT = "https://api.onkernel.com"
# Retrieved from the Kernel dashboard billing response. Kernel bills
# browser runtime in GB-seconds; the managed browser allocation is 8 GB.
KERNEL_BROWSER_GB = 8
KERNEL_BROWSER_RATE_PER_GB_SECOND = 0.0000166667
ORIGIN = "https://1337x.st"
REQUEST_LOCK = threading.Lock()
METRICS_LOCK = threading.Lock()
STATE_DIRECTORY = os.environ.get("STATE_DIRECTORY", "/var/lib/1337x-bridge")
DATABASE_PATH = os.path.join(STATE_DIRECTORY, "usage.sqlite3")
METRICS = {
    "started_at": time.time(),
    "in_flight": 0,
    "last_usage_refresh": 0.0,
}

os.makedirs(STATE_DIRECTORY, exist_ok=True)

def database():
    connection = sqlite3.connect(DATABASE_PATH, timeout=5)
    connection.execute("PRAGMA journal_mode=WAL")
    return connection

with database() as connection:
    connection.execute("""
        CREATE TABLE IF NOT EXISTS provider_events (
            id INTEGER PRIMARY KEY,
            timestamp REAL NOT NULL,
            provider TEXT NOT NULL,
            success INTEGER NOT NULL,
            elapsed_seconds REAL NOT NULL
        )
    """)
    connection.execute("""
        CREATE TABLE IF NOT EXISTS provider_usage (
            provider TEXT PRIMARY KEY,
            fetched_at REAL NOT NULL,
            payload TEXT NOT NULL
        )
    """)
    connection.execute("""
        CREATE TABLE IF NOT EXISTS provider_auth (
            name TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at REAL NOT NULL
        )
    """)

def store_usage(provider, payload):
    with database() as connection:
        connection.execute(
            "INSERT OR REPLACE INTO provider_usage(provider, fetched_at, payload) VALUES (?, ?, ?)",
            (provider, time.time(), json.dumps(payload)),
        )

def clear_usage(provider):
    with database() as connection:
        connection.execute("DELETE FROM provider_usage WHERE provider = ?", (provider,))

def stored_auth(name, fallback):
    with database() as connection:
        row = connection.execute(
            "SELECT value FROM provider_auth WHERE name = ?", (name,)
        ).fetchone()
    return row[0] if row else fallback

def store_auth(name, value):
    with database() as connection:
        connection.execute(
            "INSERT OR REPLACE INTO provider_auth(name, value, updated_at) VALUES (?, ?, ?)",
            (name, value, time.time()),
        )

def refresh_kernel_dashboard_cookie():
    cookie_header = stored_auth(
        "kernel_dashboard_cookie", credential("kernel-dashboard-cookie")
    )
    jar = SimpleCookie()
    jar.load(cookie_header)

    def update_jar(response):
        for set_cookie in response.headers.get_all("Set-Cookie") or []:
            replacement = SimpleCookie()
            replacement.load(set_cookie)
            for name, morsel in replacement.items():
                jar[name] = morsel.value

    def cookie_value():
        return "; ".join(f"{name}={morsel.value}" for name, morsel in jar.items())

    headers = {
        "Origin": "https://dashboard.onkernel.com",
        "Referer": "https://dashboard.onkernel.com/",
        "User-Agent": "Mozilla/5.0",
    }
    # Clerk sessions use short-lived tokens.  `/v1/client` merely reads
    # the session; the Clerk frontend uses this touch route to keep it
    # alive while the dashboard is open, then mints a new JWT.
    touch_url = (
        "https://clerk.onkernel.com/v1/client/touch?"
        + urllib.parse.urlencode({"redirect_url": "https://dashboard.onkernel.com/"})
    )
    request = urllib.request.Request(
        touch_url,
        headers={**headers, "Cookie": cookie_value()},
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        response.read()
        update_jar(response)
    client_request = urllib.request.Request(
        "https://clerk.onkernel.com/v1/client",
        headers={**headers, "Cookie": cookie_value()},
    )
    with urllib.request.urlopen(client_request, timeout=15) as response:
        client = json.load(response).get("response", {})
        update_jar(response)
    session_id = client.get("last_active_session_id")
    if not session_id:
        raise RuntimeError("Kernel dashboard Clerk session is not authenticated")
    token_request = urllib.request.Request(
        "https://clerk.onkernel.com/v1/client/sessions/" + urllib.parse.quote(session_id, safe="") + "/tokens",
        data=b"{}",
        method="POST",
        headers={
            **headers,
            "Cookie": cookie_value(),
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(token_request, timeout=15) as response:
        minted = json.load(response)
        update_jar(response)
    if not minted.get("jwt"):
        raise RuntimeError("Kernel dashboard Clerk token mint returned no JWT")
    jar["__session"] = minted["jwt"]
    refreshed = cookie_value()
    store_auth("kernel_dashboard_cookie", refreshed)
    return refreshed

def refresh_provider_usage():
    with METRICS_LOCK:
        if time.time() - METRICS["last_usage_refresh"] < 60:
            return
        METRICS["last_usage_refresh"] = time.time()
    try:
        token = credential("browserless-api-key")
        url = "https://api.browserless.io/v1/account/usage?token=" + urllib.parse.quote(token, safe="")
        with urllib.request.urlopen(url, timeout=15) as response:
            store_usage("browserless_account", json.load(response))
    except (OSError, RuntimeError, ValueError, urllib.error.URLError) as error:
        store_usage("browserless_account_error", {"error": type(error).__name__})
    try:
        token = credential("kernel-api-key")
        request = urllib.request.Request(
            "https://api.onkernel.com/browsers?include_deleted=true&limit=100",
            headers={"Authorization": "Bearer " + token},
        )
        with urllib.request.urlopen(request, timeout=15) as response:
            sessions = json.load(response)
        uptime_ms = sum(session.get("usage", {}).get("uptime_ms", 0) for session in sessions)
        store_usage("kernel_sessions", {
            "session_count": len(sessions),
            "uptime_ms": uptime_ms,
            "browser_gb": KERNEL_BROWSER_GB,
            "rate_per_gb_second_usd": KERNEL_BROWSER_RATE_PER_GB_SECOND,
            "calculated_browser_cost_usd": uptime_ms / 1000 * KERNEL_BROWSER_GB * KERNEL_BROWSER_RATE_PER_GB_SECOND,
            "source": "Actual Kernel browser-session API usage, priced in GB-seconds.",
        })
    except (OSError, RuntimeError, ValueError, urllib.error.URLError) as error:
        store_usage("kernel_sessions_error", {"error": type(error).__name__})
    try:
        cookie = stored_auth(
            "kernel_dashboard_cookie", credential("kernel-dashboard-cookie")
        )
        headers = {
            "Cookie": cookie,
            "Origin": "https://dashboard.onkernel.com",
            "Referer": "https://dashboard.onkernel.com/",
            "User-Agent": "Mozilla/5.0",
        }
        plan_request = urllib.request.Request(
            "https://dashboard.onkernel.com/api/billing/plan",
            headers=headers,
        )
        usage_request = urllib.request.Request(
            "https://dashboard.onkernel.com/api/billing/usage"
            "?range=30d&project_id=wogw5mup5h5wpbx9ajq0j4hn",
            headers=headers,
        )
        with urllib.request.urlopen(plan_request, timeout=15) as response:
            plan = json.load(response)
        with urllib.request.urlopen(usage_request, timeout=15) as response:
            usage = json.load(response)
        spent = sum(float(item.get("total", 0)) for item in usage.get("spend", []))
        allowance = 5.0 if plan.get("currentPlan") == "FREE" else None
        store_usage("kernel_billing", {
            "plan": plan.get("currentPlan"),
            "plan_status": plan.get("planStatus"),
            "has_payment_method": plan.get("hasPaymentMethod"),
            "spent_usd": spent,
            "allowance_usd": allowance,
            "remaining_usd": max(0, allowance - spent) if allowance is not None else None,
            "spend": usage.get("spend", []),
            "usage": usage.get("usage", []),
            "source": "Live Kernel billing APIs with service-refreshed Clerk authentication",
        })
        clear_usage("kernel_billing_error")
    except (OSError, RuntimeError, ValueError, urllib.error.URLError) as error:
        store_usage("kernel_billing_error", {"error": type(error).__name__})

def call_provider(name, action):
    started = time.monotonic()
    try:
        value = action()
    except Exception:
        with database() as connection:
            connection.execute(
                "INSERT INTO provider_events(timestamp, provider, success, elapsed_seconds) VALUES (?, ?, ?, ?)",
                (time.time(), name, 0, time.monotonic() - started),
            )
        raise
    with database() as connection:
        connection.execute(
            "INSERT INTO provider_events(timestamp, provider, success, elapsed_seconds) VALUES (?, ?, ?, ?)",
            (time.time(), name, 1, time.monotonic() - started),
        )
    return value

def metrics_snapshot():
    refresh_provider_usage()
    with database() as connection:
        rows = connection.execute("""
            SELECT provider, COUNT(*), COALESCE(SUM(success), 0),
                   COUNT(*) - COALESCE(SUM(success), 0), COALESCE(SUM(elapsed_seconds), 0)
            FROM provider_events GROUP BY provider
        """).fetchall()
        usage_rows = connection.execute(
            "SELECT provider, fetched_at, payload FROM provider_usage"
        ).fetchall()
    providers = {
        name: {
            "attempts": attempts,
            "successes": successes,
            "failures": failures,
            "elapsed_seconds": round(elapsed, 2),
        }
        for name, attempts, successes, failures, elapsed in rows
    }
    for name in ("browserless", "kernel", "flaresolverr"):
        providers.setdefault(name, {"attempts": 0, "successes": 0, "failures": 0, "elapsed_seconds": 0.0})
    with METRICS_LOCK:
        return {
            "uptime_seconds": round(time.time() - METRICS["started_at"], 1),
            "in_flight": METRICS["in_flight"],
            "persistent_database": DATABASE_PATH,
            "providers": providers,
            "provider_api_usage": {
                provider: {"fetched_at": fetched_at, "data": json.loads(payload)}
                for provider, fetched_at, payload in usage_rows
            },
        }

def credential(name):
    credential_dir = os.environ.get("CREDENTIALS_DIRECTORY")
    if not credential_dir:
        raise RuntimeError(f"{name} credential is unavailable")
    with open(os.path.join(credential_dir, name), encoding="utf-8") as file:
        value = file.read().strip()
    if not value:
        raise RuntimeError(f"{name} credential is empty")
    return value

def browserless_fetch(path):
    token = credential("browserless-api-key")
    usage_url = "https://api.browserless.io/v1/account/usage?token=" + urllib.parse.quote(token, safe="")
    with urllib.request.urlopen(usage_url, timeout=15) as response:
        usage = json.load(response)
    remaining_units = usage.get("units", {}).get("remaining")
    if not isinstance(remaining_units, (int, float)) or remaining_units <= 0:
        raise RuntimeError("Browserless unit allowance is exhausted")
    payload = json.dumps({
        "url": ORIGIN + path,
        "content": True,
        "cookies": False,
        "screenshot": False,
        "browserWSEndpoint": False,
    }).encode()
    endpoint = BROWSERLESS_ENDPOINT + "?token=" + urllib.parse.quote(token, safe="") + "&proxy=residential"
    request = urllib.request.Request(
        endpoint,
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=110) as response:
        result = json.load(response)
    body = result.get("content")
    if not body or "/torrent/" not in body:
        raise RuntimeError("Browserless returned no 1337x results")
    return body

def kernel_fetch(path):
    token = credential("kernel-api-key")
    headers = {
        "Authorization": "Bearer " + token,
        "Content-Type": "application/json",
    }

    def request(url, data=None, timeout=75, method=None):
        payload = None if data is None else json.dumps(data).encode()
        with urllib.request.urlopen(
            urllib.request.Request(url, data=payload, headers=headers, method=method),
            timeout=timeout,
        ) as response:
            raw = response.read()
            return json.loads(raw) if raw else None

    target_url = ORIGIN + path
    browser = request(KERNEL_ENDPOINT + "/browsers", {
        "stealth": True,
        "headless": False,
        "start_url": target_url,
        "timeout_seconds": 120,
    }, timeout=30)
    session_id = browser.get("session_id")
    if not session_id:
        raise RuntimeError("Kernel returned no browser session")
    try:
        code = """
          try {
            await page.waitForFunction(
              () => document.querySelectorAll('a[href*=\"/torrent/\"]').length > 0,
              {timeout: 55000},
            );
          } catch (_) {}
          return await page.content();
        """
        result = request(
            KERNEL_ENDPOINT + "/browsers/" + urllib.parse.quote(session_id, safe="") + "/playwright/execute",
            {"code": code, "timeout_sec": 120},
            timeout=125,
        )
        body = result.get("result")
        if not isinstance(body, str) or "/torrent/" not in body:
            raise RuntimeError("Kernel returned no 1337x results")
        return body
    finally:
        # Browser time is billable; delete every short-lived fallback session.
        try:
            request(
                KERNEL_ENDPOINT + "/browsers/" + urllib.parse.quote(session_id, safe=""),
                method="DELETE",
                timeout=20,
            )
        except (OSError, urllib.error.URLError):
            pass

def flaresolverr_fetch(path):
    payload = json.dumps({
        "cmd": "request.get",
        "url": ORIGIN + path,
        "maxTimeout": 60000,
    }).encode()
    request = urllib.request.Request(
        FLARESOLVERR_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=75) as response:
        result = json.load(response)
    solution = result.get("solution", {})
    body = solution.get("response")
    if result.get("status") != "ok" or body is None:
        raise RuntimeError("FlareSolverr returned no solution")
    return body, solution.get("status", 502)

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        with METRICS_LOCK:
            METRICS["in_flight"] += 1
        try:
            # Avoid concurrent browser challenges and paid-proxy requests.
            with REQUEST_LOCK:
                try:
                    body = call_provider("browserless", lambda: browserless_fetch(self.path))
                    status = 200
                except (OSError, RuntimeError, ValueError, urllib.error.URLError):
                    try:
                        body = call_provider("kernel", lambda: kernel_fetch(self.path))
                        status = 200
                    except (OSError, RuntimeError, ValueError, urllib.error.URLError):
                        body, status = call_provider("flaresolverr", lambda: flaresolverr_fetch(self.path))
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body.encode())))
            self.end_headers()
            self.wfile.write(body.encode())
        except (OSError, RuntimeError, ValueError, urllib.error.URLError) as error:
            body = b"1337x bridge upstream unavailable"
            self.send_response(502)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        finally:
            with METRICS_LOCK:
                METRICS["in_flight"] -= 1

    def log_message(self, format, *args):
        pass

class StatsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        snapshot = metrics_snapshot()
        if self.path == "/metrics":
            body = json.dumps(snapshot, indent=2).encode()
            content_type = "application/json; charset=utf-8"
        elif self.path == "/" or self.path == "/index.html":
            payload = json.dumps(snapshot, indent=2)
            body = ("<!doctype html><title>1337x bridge costs</title>"
                "<style>body{background:#101218;color:#e8eaf0;font:16px system-ui;margin:3rem}pre{background:#181b24;padding:1.5rem;border-radius:8px}</style>"
                "<h1>1337x bridge usage</h1><p>Refreshes every 10 seconds. <a href='/metrics'>JSON</a></p>"
                "<pre id='metrics'></pre><script>const e=document.getElementById('metrics');async function f(){e.textContent=JSON.stringify(await fetch('/metrics').then(r=>r.json()),null,2)}f();setInterval(f,10000)</script>").encode()
            content_type = "text/html; charset=utf-8"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass

def usage_refresh_loop():
    while True:
        refresh_provider_usage()
        time.sleep(60)

def kernel_session_heartbeat_loop():
    time.sleep(10)
    while True:
        try:
            refresh_kernel_dashboard_cookie()
        except Exception:
            pass
        time.sleep(30)

threading.Thread(target=usage_refresh_loop, daemon=True).start()
threading.Thread(target=kernel_session_heartbeat_loop, daemon=True).start()
threading.Thread(
    target=ThreadingHTTPServer(("0.0.0.0", 1337), StatsHandler).serve_forever,
    daemon=True,
).start()
HTTPServer(("127.0.0.1", 8192), Handler).serve_forever()
