import hashlib
import json
import os
import re
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import namedtuple
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BROWSERLESS_CLOUD_ENDPOINT = "https://production-sfo.browserless.io/unblock"
FLARESOLVERR_URL = "http://127.0.0.1:8191/v1"
FLARESOLVERR_SESSION = "1337x-bridge"
KERNEL_ENDPOINT = "https://api.onkernel.com"
KERNEL_BROWSER_RATE_PER_GB_SECOND = 0.0000166667
KERNEL_SPEND_LIMIT_USD = 4.90
KERNEL_BILLING_MAX_AGE_SECONDS = 120
KERNEL_HEADLESS = os.environ.get("KERNEL_HEADLESS", "false").lower() == "true"
KERNEL_BROWSER_GB = 1 if KERNEL_HEADLESS else 8
ORIGIN = "https://1337x.st"

CACHE_TTL_SECONDS = 30
CACHE_MAX_ENTRIES = 128
CIRCUIT_FAILURE_THRESHOLD = 3
CIRCUIT_OPEN_SECONDS = 600
LOCAL_PROVIDER_ORDER = tuple(
    item.strip()
    for item in os.environ.get(
        "LOCAL_PROVIDER_ORDER", "flaresolverr"
    ).split(",")
    if item.strip()
)
CIRCUIT_CONFIG = {
    "flaresolverr": {
        "failure_threshold": CIRCUIT_FAILURE_THRESHOLD,
        "open_seconds": CIRCUIT_OPEN_SECONDS,
    },
    # Kernel is metered. Two strict failures stop further spend for an hour;
    # its live billing hard cap remains the final backstop.
    "kernel": {"failure_threshold": 2, "open_seconds": 3600},
}

REQUEST_LOCK = threading.Lock()
METRICS_LOCK = threading.Lock()
CACHE_LOCK = threading.Lock()
FLIGHTS_LOCK = threading.Lock()
CIRCUIT_LOCK = threading.Lock()
STATE_DIRECTORY = os.environ.get("STATE_DIRECTORY", "/var/lib/1337x-bridge")
DATABASE_PATH = os.path.join(STATE_DIRECTORY, "usage.sqlite3")
UpstreamResponse = namedtuple("UpstreamResponse", "body status outcome")

METRICS = {
    "started_at": time.time(),
    "in_flight": 0,
    "last_usage_refresh": 0.0,
    "cache_hits": 0,
    "cache_misses": 0,
    "coalesced_requests": 0,
}
CACHE = {}
FLIGHTS = {}
CIRCUITS = {
    provider: {"consecutive_failures": 0, "open_until": 0.0}
    for provider in CIRCUIT_CONFIG
}


class ProviderError(RuntimeError):
    def __init__(self, category, message):
        super().__init__(message)
        self.category = category


os.makedirs(STATE_DIRECTORY, exist_ok=True)


def database():
    connection = sqlite3.connect(DATABASE_PATH, timeout=5)
    connection.execute("PRAGMA journal_mode=WAL")
    return connection


def initialize_database():
    with database() as connection:
        connection.execute("""
            CREATE TABLE IF NOT EXISTS provider_events (
                id INTEGER PRIMARY KEY,
                timestamp REAL NOT NULL,
                provider TEXT NOT NULL,
                success INTEGER NOT NULL,
                elapsed_seconds REAL NOT NULL,
                path_hash TEXT,
                outcome TEXT,
                error_type TEXT,
                error_message TEXT
            )
        """)
        existing = {
            row[1]
            for row in connection.execute("PRAGMA table_info(provider_events)")
        }
        for name, sql_type in (
            ("path_hash", "TEXT"),
            ("outcome", "TEXT"),
            ("error_type", "TEXT"),
            ("error_message", "TEXT"),
        ):
            if name not in existing:
                connection.execute(
                    f"ALTER TABLE provider_events ADD COLUMN {name} {sql_type}"
                )
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


initialize_database()


def path_hash(path):
    return hashlib.sha256(path.encode()).hexdigest()[:12]


def store_usage(provider, payload):
    with database() as connection:
        connection.execute(
            "INSERT OR REPLACE INTO provider_usage(provider, fetched_at, payload) VALUES (?, ?, ?)",
            (provider, time.time(), json.dumps(payload)),
        )


def clear_usage(provider):
    with database() as connection:
        connection.execute("DELETE FROM provider_usage WHERE provider = ?", (provider,))


def read_usage(provider):
    with database() as connection:
        row = connection.execute(
            "SELECT fetched_at, payload FROM provider_usage WHERE provider = ?",
            (provider,),
        ).fetchone()
    if not row:
        return None
    return {"fetched_at": row[0], "data": json.loads(row[1])}


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


def credential(name):
    credential_dir = os.environ.get("CREDENTIALS_DIRECTORY")
    if not credential_dir:
        raise RuntimeError(f"{name} credential is unavailable")
    with open(os.path.join(credential_dir, name), encoding="utf-8") as file:
        value = file.read().strip()
    if not value:
        raise RuntimeError(f"{name} credential is empty")
    return value


def classify_1337x_html(body):
    if not isinstance(body, str) or not body.strip():
        return "malformed"
    lower = body.lower()
    if re.search(r'href=["\'][^"\']*/torrent/', lower):
        return "results"
    empty_markers = (
        "no results were returned",
        "no results found",
        "no torrents found",
        "nothing found",
    )
    site_markers = ("1337x", "torrent search", "search torrents")
    # 1337x's legitimate empty-result page is titled "Error something went
    # wrong" and includes Cloudflare's analytics script. Recognize its explicit
    # no-results message before applying challenge-page heuristics.
    if any(marker in lower for marker in empty_markers) and any(
        marker in lower for marker in site_markers
    ):
        return "empty"
    challenge_markers = (
        "error something went wrong",
        "attention required! | cloudflare",
        "cf-chl-",
        "cloudflare ray id",
        "just a moment...",
        "verify you are human",
        "captcha",
        "access denied",
    )
    if any(marker in lower for marker in challenge_markers):
        return "challenge"
    return "malformed"


def validated_response(body, status=200):
    outcome = classify_1337x_html(body)
    if outcome not in ("results", "empty"):
        raise ProviderError(outcome, f"1337x response classified as {outcome}")
    return UpstreamResponse(body, status if isinstance(status, int) else 200, outcome)


def error_category(error):
    if isinstance(error, ProviderError):
        return error.category
    if isinstance(error, TimeoutError):
        return "timeout"
    if isinstance(error, urllib.error.HTTPError):
        return "http_" + str(error.code)
    if isinstance(error, (OSError, urllib.error.URLError)):
        return "transport"
    if isinstance(error, (ValueError, json.JSONDecodeError)):
        return "malformed"
    return type(error).__name__


def record_event(provider, path, success, elapsed, outcome, error=None):
    with database() as connection:
        connection.execute(
            """
            INSERT INTO provider_events(
                timestamp, provider, success, elapsed_seconds, path_hash,
                outcome, error_type, error_message
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                time.time(),
                provider,
                int(success),
                elapsed,
                path_hash(path),
                outcome,
                None if error is None else type(error).__name__,
                None if error is None else str(error)[:240],
            ),
        )


def circuit_available(provider):
    if provider not in CIRCUIT_CONFIG:
        return True
    with CIRCUIT_LOCK:
        return CIRCUITS[provider]["open_until"] <= time.time()


def update_circuit(provider, success, category=None):
    if provider not in CIRCUIT_CONFIG:
        return
    with CIRCUIT_LOCK:
        circuit = CIRCUITS[provider]
        if success:
            circuit["consecutive_failures"] = 0
            circuit["open_until"] = 0.0
            return
        if category not in (
            "challenge",
            "challenge_timeout",
            "timeout",
            "transport",
            "malformed",
        ):
            return
        circuit["consecutive_failures"] += 1
        config = CIRCUIT_CONFIG[provider]
        if circuit["consecutive_failures"] >= config["failure_threshold"]:
            circuit["open_until"] = time.time() + config["open_seconds"]


def call_provider(name, path, action):
    if not circuit_available(name):
        raise ProviderError("circuit_open", f"{name} circuit is open")
    started = time.monotonic()
    try:
        value = action()
    except Exception as error:
        category = error_category(error)
        elapsed = time.monotonic() - started
        record_event(name, path, False, elapsed, category, error)
        update_circuit(name, False, category)
        raise
    elapsed = time.monotonic() - started
    record_event(name, path, True, elapsed, value.outcome)
    update_circuit(name, True)
    return value


def cache_get(path, record_metric=True):
    now = time.monotonic()
    with CACHE_LOCK:
        entry = CACHE.get(path)
        if entry and entry["expires_at"] > now:
            if record_metric:
                with METRICS_LOCK:
                    METRICS["cache_hits"] += 1
            return entry["response"]
        if entry:
            CACHE.pop(path, None)
        if record_metric:
            with METRICS_LOCK:
                METRICS["cache_misses"] += 1
    return None


def cache_put(path, response):
    with CACHE_LOCK:
        if len(CACHE) >= CACHE_MAX_ENTRIES:
            oldest = min(CACHE, key=lambda key: CACHE[key]["created_at"])
            CACHE.pop(oldest, None)
        CACHE[path] = {
            "created_at": time.monotonic(),
            "expires_at": time.monotonic() + CACHE_TTL_SECONDS,
            "response": response,
        }


def begin_flight(path):
    with FLIGHTS_LOCK:
        if path in FLIGHTS:
            with METRICS_LOCK:
                METRICS["coalesced_requests"] += 1
            return False, FLIGHTS[path]
        event = threading.Event()
        FLIGHTS[path] = event
        return True, event


def end_flight(path):
    with FLIGHTS_LOCK:
        event = FLIGHTS.pop(path, None)
        if event:
            event.set()


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
    touch_url = (
        "https://clerk.onkernel.com/v1/client/touch?"
        + urllib.parse.urlencode({"redirect_url": "https://dashboard.onkernel.com/"})
    )
    request = urllib.request.Request(
        touch_url, headers={**headers, "Cookie": cookie_value()}
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
        "https://clerk.onkernel.com/v1/client/sessions/"
        + urllib.parse.quote(session_id, safe="")
        + "/tokens",
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


def refresh_provider_usage(force=False):
    with METRICS_LOCK:
        if not force and time.time() - METRICS["last_usage_refresh"] < 60:
            return
        METRICS["last_usage_refresh"] = time.time()
    try:
        token = credential("browserless-api-key")
        url = (
            "https://api.browserless.io/v1/account/usage?token="
            + urllib.parse.quote(token, safe="")
        )
        with urllib.request.urlopen(url, timeout=15) as response:
            store_usage("browserless_account", json.load(response))
        clear_usage("browserless_account_error")
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
        if isinstance(sessions, dict):
            sessions = sessions.get("browsers", sessions.get("sessions", []))
        uptime_ms = sum(
            session.get("usage", {}).get("uptime_ms", 0) for session in sessions
        )
        store_usage(
            "kernel_sessions",
            {
                "session_count": len(sessions),
                "uptime_ms": uptime_ms,
                "browser_gb": KERNEL_BROWSER_GB,
                "rate_per_gb_second_usd": KERNEL_BROWSER_RATE_PER_GB_SECOND,
                "calculated_browser_cost_usd": (
                    uptime_ms
                    / 1000
                    * KERNEL_BROWSER_GB
                    * KERNEL_BROWSER_RATE_PER_GB_SECOND
                ),
                "source": "Actual Kernel browser-session API usage, priced in GB-seconds.",
            },
        )
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
            "https://dashboard.onkernel.com/api/billing/plan", headers=headers
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
        store_usage(
            "kernel_billing",
            {
                "plan": plan.get("currentPlan"),
                "plan_status": plan.get("planStatus"),
                "has_payment_method": plan.get("hasPaymentMethod"),
                "spent_usd": spent,
                "allowance_usd": allowance,
                "spend_limit_usd": KERNEL_SPEND_LIMIT_USD,
                "remaining_usd": (
                    max(0, allowance - spent) if allowance is not None else None
                ),
                "spend": usage.get("spend", []),
                "usage": usage.get("usage", []),
                "source": (
                    "Live Kernel billing APIs with service-refreshed Clerk authentication"
                ),
            },
        )
        clear_usage("kernel_billing_error")
    except (OSError, RuntimeError, ValueError, urllib.error.URLError) as error:
        store_usage("kernel_billing_error", {"error": type(error).__name__})


def browserless_cloud_fetch(path):
    usage = read_usage("browserless_account")
    if not usage or time.time() - usage["fetched_at"] > 90:
        refresh_provider_usage(force=True)
        usage = read_usage("browserless_account")
    remaining = (
        usage.get("data", {}).get("units", {}).get("remaining") if usage else None
    )
    if not isinstance(remaining, (int, float)):
        raise ProviderError("usage_unavailable", "Browserless usage is unavailable")
    if remaining <= 0:
        raise ProviderError("spend_cap", "Browserless unit allowance is exhausted")
    token = credential("browserless-api-key")
    payload = json.dumps(
        {
            "url": ORIGIN + path,
            "content": True,
            "cookies": False,
            "screenshot": False,
            "browserWSEndpoint": False,
        }
    ).encode()
    endpoint = (
        BROWSERLESS_CLOUD_ENDPOINT
        + "?token="
        + urllib.parse.quote(token, safe="")
        + "&proxy=residential"
    )
    request = urllib.request.Request(
        endpoint, data=payload, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(request, timeout=110) as response:
        result = json.load(response)
    return validated_response(result.get("content"))


def flaresolverr_command(payload, timeout=35):
    request = urllib.request.Request(
        FLARESOLVERR_URL,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8", "replace")
        lower = raw.lower()
        if "solving the challenge" in lower or "challenge" in lower:
            raise ProviderError(
                "challenge_timeout", "FlareSolverr challenge timed out"
            ) from error
        if "session doesn't exist" in lower or "session does not exist" in lower:
            raise ProviderError("session_missing", "FlareSolverr session is missing") from error
        raise


def reset_flaresolverr_session():
    try:
        flaresolverr_command(
            {"cmd": "sessions.destroy", "session": FLARESOLVERR_SESSION}, timeout=15
        )
    except Exception:
        pass
    result = flaresolverr_command(
        {"cmd": "sessions.create", "session": FLARESOLVERR_SESSION}, timeout=30
    )
    if result.get("status") != "ok":
        raise ProviderError("transport", "FlareSolverr could not create its session")


def ensure_flaresolverr_session():
    result = flaresolverr_command({"cmd": "sessions.list"}, timeout=15)
    sessions = result.get("sessions", [])
    names = {
        item.get("session") if isinstance(item, dict) else item for item in sessions
    }
    if FLARESOLVERR_SESSION not in names:
        reset_flaresolverr_session()


def flaresolverr_fetch_once(path):
    result = flaresolverr_command(
        {
            "cmd": "request.get",
            "url": ORIGIN + path,
            "session": FLARESOLVERR_SESSION,
            "session_ttl_minutes": 30,
            "maxTimeout": 25000,
            "disableMedia": True,
        },
        timeout=35,
    )
    if result.get("status") != "ok":
        raise ProviderError("transport", "FlareSolverr request failed")
    solution = result.get("solution", {})
    return validated_response(solution.get("response"), solution.get("status", 200))


def flaresolverr_fetch(path):
    ensure_flaresolverr_session()
    try:
        return flaresolverr_fetch_once(path)
    except ProviderError as first_error:
        if first_error.category not in ("challenge", "malformed", "session_missing"):
            raise
        reset_flaresolverr_session()
        return flaresolverr_fetch_once(path)


def kernel_headers():
    return {
        "Authorization": "Bearer " + credential("kernel-api-key"),
        "Content-Type": "application/json",
    }


def kernel_request(url, data=None, timeout=75, method=None):
    payload = None if data is None else json.dumps(data).encode()
    with urllib.request.urlopen(
        urllib.request.Request(
            url, data=payload, headers=kernel_headers(), method=method
        ),
        timeout=timeout,
    ) as response:
        raw = response.read()
        return json.loads(raw) if raw else None


def kernel_active_session_ids():
    result = kernel_request(
        KERNEL_ENDPOINT + "/browsers?include_deleted=false&limit=100", timeout=20
    )
    if isinstance(result, dict):
        result = result.get("browsers", result.get("sessions", []))
    return {
        item.get("session_id")
        for item in (result or [])
        if item.get("session_id") and not item.get("deleted_at")
    }


def delete_kernel_session(session_id):
    kernel_request(
        KERNEL_ENDPOINT + "/browsers/" + urllib.parse.quote(session_id, safe=""),
        method="DELETE",
        timeout=20,
    )


def cleanup_new_kernel_sessions(previous_ids):
    removed = []
    for attempt in range(3):
        try:
            new_ids = kernel_active_session_ids() - previous_ids
            for session_id in new_ids:
                try:
                    delete_kernel_session(session_id)
                    removed.append(session_id)
                except Exception:
                    pass
            if new_ids:
                break
        except Exception:
            pass
        if attempt < 2:
            time.sleep(2)
    return removed


def enforce_kernel_cap():
    billing = read_usage("kernel_billing")
    if not billing:
        raise ProviderError("usage_unavailable", "Kernel billing data is unavailable")
    if time.time() - billing["fetched_at"] > KERNEL_BILLING_MAX_AGE_SECONDS:
        raise ProviderError("usage_stale", "Kernel billing data is stale")
    spent = billing["data"].get("spent_usd")
    if not isinstance(spent, (int, float)):
        raise ProviderError("usage_unavailable", "Kernel billing spend is unavailable")
    if spent >= KERNEL_SPEND_LIMIT_USD:
        raise ProviderError("spend_cap", "Kernel spend limit reached")


def kernel_fetch(path, headless=None):
    enforce_kernel_cap()
    if headless is None:
        headless = KERNEL_HEADLESS
    previous_ids = kernel_active_session_ids()
    session_id = None
    try:
        try:
            browser = kernel_request(
                KERNEL_ENDPOINT + "/browsers",
                {
                    "stealth": True,
                    "headless": bool(headless),
                    "timeout_seconds": 90,
                },
                timeout=45,
            )
        except Exception:
            cleanup_new_kernel_sessions(previous_ids)
            raise
        session_id = browser.get("session_id") if browser else None
        if not session_id:
            cleanup_new_kernel_sessions(previous_ids)
            raise ProviderError("malformed", "Kernel returned no browser session")
        target_url = json.dumps(ORIGIN + path)
        code = f"""
          try {{
            await page.goto({target_url}, {{
              waitUntil: "domcontentloaded",
              timeout: 45000,
            }});
          }} catch (_) {{}}
          try {{
            await page.waitForFunction(
              () => {{
                const text = document.body.innerText;
                return document.querySelector('a[href*="/torrent/"]')
                  || (
                    /no (results|torrents)|nothing found/i.test(text)
                    && !/cloudflare|captcha|something went wrong/i.test(text)
                  );
              }},
              {{timeout: 35000}},
            );
          }} catch (_) {{}}
          return await page.content();
        """
        result = kernel_request(
            KERNEL_ENDPOINT
            + "/browsers/"
            + urllib.parse.quote(session_id, safe="")
            + "/playwright/execute",
            {"code": code, "timeout_sec": 75},
            timeout=85,
        )
        return validated_response(result.get("result") if result else None)
    finally:
        if session_id:
            try:
                delete_kernel_session(session_id)
            except Exception:
                pass


def route_request(path):
    actions = {
        "flaresolverr": lambda: flaresolverr_fetch(path),
        "browserless_cloud": lambda: browserless_cloud_fetch(path),
        "kernel": lambda: kernel_fetch(path),
    }
    errors = []
    for provider in LOCAL_PROVIDER_ORDER + ("browserless_cloud", "kernel"):
        try:
            return call_provider(provider, path, actions[provider])
        except (
            OSError,
            RuntimeError,
            ValueError,
            urllib.error.URLError,
        ) as error:
            errors.append(f"{provider}:{error_category(error)}")
    raise ProviderError("all_failed", ", ".join(errors))


def metrics_snapshot():
    refresh_provider_usage()
    since = time.time() - 3600
    with database() as connection:
        rows = connection.execute("""
            SELECT provider, COUNT(*), COALESCE(SUM(success), 0),
                   COUNT(*) - COALESCE(SUM(success), 0),
                   COALESCE(SUM(elapsed_seconds), 0)
            FROM provider_events GROUP BY provider
        """).fetchall()
        recent_rows = connection.execute(
            """
            SELECT provider, COUNT(*), COALESCE(SUM(success), 0)
            FROM provider_events WHERE timestamp >= ? GROUP BY provider
            """,
            (since,),
        ).fetchall()
        error_rows = connection.execute(
            """
            SELECT provider, outcome, COUNT(*)
            FROM provider_events
            WHERE success = 0 AND timestamp >= ?
            GROUP BY provider, outcome
            """,
            (since,),
        ).fetchall()
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
    for name in (
        "flaresolverr",
        "browserless_cloud",
        "kernel",
    ):
        providers.setdefault(
            name,
            {
                "attempts": 0,
                "successes": 0,
                "failures": 0,
                "elapsed_seconds": 0.0,
            },
        )
    for name, attempts, successes in recent_rows:
        providers.setdefault(name, {})["recent_1h"] = {
            "attempts": attempts,
            "successes": successes,
            "success_rate": round(successes / attempts, 4) if attempts else None,
        }
    recent_errors = {}
    for provider, outcome, count in error_rows:
        recent_errors.setdefault(provider, {})[outcome or "unknown"] = count
    now = time.time()
    with CIRCUIT_LOCK:
        circuits = {
            provider: {
                "state": "open" if state["open_until"] > now else "closed",
                "consecutive_failures": state["consecutive_failures"],
                "open_for_seconds": round(max(0, state["open_until"] - now), 1),
            }
            for provider, state in CIRCUITS.items()
        }
    with CACHE_LOCK:
        cache_entries = sum(
            1 for entry in CACHE.values() if entry["expires_at"] > time.monotonic()
        )
    with METRICS_LOCK:
        runtime = {
            "uptime_seconds": round(time.time() - METRICS["started_at"], 1),
            "in_flight": METRICS["in_flight"],
            "cache": {
                "ttl_seconds": CACHE_TTL_SECONDS,
                "entries": cache_entries,
                "hits": METRICS["cache_hits"],
                "misses": METRICS["cache_misses"],
                "coalesced_requests": METRICS["coalesced_requests"],
            },
        }
    return {
        **runtime,
        "persistent_database": DATABASE_PATH,
        "routing": {
            "selected_local_engine": LOCAL_PROVIDER_ORDER[0],
            "provider_order": list(
                LOCAL_PROVIDER_ORDER + ("browserless_cloud", "kernel")
            ),
            "kernel_headless": KERNEL_HEADLESS,
        },
        "caps": {
            "browserless_cloud_requires_positive_remaining_units": True,
            "kernel_spend_limit_usd": KERNEL_SPEND_LIMIT_USD,
            "kernel_billing_max_age_seconds": KERNEL_BILLING_MAX_AGE_SECONDS,
        },
        "circuits": circuits,
        "providers": providers,
        "recent_errors_1h": recent_errors,
        "provider_api_usage": {
            provider: {"fetched_at": fetched_at, "data": json.loads(payload)}
            for provider, fetched_at, payload in usage_rows
        },
    }


class Handler(BaseHTTPRequestHandler):
    def write_response(self, response):
        encoded = response.body.encode()
        self.send_response(response.status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("X-1337x-Outcome", response.outcome)
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self):
        with METRICS_LOCK:
            METRICS["in_flight"] += 1
        leader = False
        try:
            cached = cache_get(self.path)
            if cached:
                self.write_response(cached)
                return
            leader, event = begin_flight(self.path)
            if not leader:
                event.wait(180)
                cached = cache_get(self.path, record_metric=False)
                if not cached:
                    raise ProviderError(
                        "coalesced_failed", "The leading request did not populate cache"
                    )
                self.write_response(cached)
                return
            with REQUEST_LOCK:
                cached = cache_get(self.path, record_metric=False)
                if cached:
                    self.write_response(cached)
                    return
                response = route_request(self.path)
                cache_put(self.path, response)
            self.write_response(response)
        except (
            OSError,
            RuntimeError,
            ValueError,
            urllib.error.URLError,
        ):
            body = b"1337x bridge upstream unavailable"
            self.send_response(502)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        finally:
            if leader:
                end_flight(self.path)
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
        elif self.path in ("/", "/index.html"):
            body = (
                "<!doctype html><title>1337x bridge costs</title>"
                "<style>body{background:#101218;color:#e8eaf0;font:16px "
                "system-ui;margin:3rem}pre{background:#181b24;padding:1.5rem;"
                "border-radius:8px}a{color:#8ab4f8}</style>"
                "<h1>1337x bridge usage</h1><p>Refreshes every 10 seconds. "
                "<a href='/metrics'>JSON</a></p><pre id='metrics'></pre>"
                "<script>const e=document.getElementById('metrics');async function "
                "f(){e.textContent=JSON.stringify(await fetch('/metrics').then("
                "r=>r.json()),null,2)}f();setInterval(f,10000)</script>"
            ).encode()
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


def main():
    threading.Thread(target=usage_refresh_loop, daemon=True).start()
    threading.Thread(target=kernel_session_heartbeat_loop, daemon=True).start()
    threading.Thread(
        target=ThreadingHTTPServer(
            ("0.0.0.0", 1337), StatsHandler
        ).serve_forever,
        daemon=True,
    ).start()
    ThreadingHTTPServer(("127.0.0.1", 8192), Handler).serve_forever()


if __name__ == "__main__":
    main()
