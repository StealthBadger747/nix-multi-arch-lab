{ config, pkgs, pkgs-unstable, lib, nixarr, ... }:
let
  host = "pilatus";
  tld = "parawell.cloud";
  fqdn = "${host}.${tld}";
  timezone = "America/Los_Angeles";
  pipxNoCheck = pkgs.pipx.overridePythonAttrs (_old: {
    doCheck = false;
  });
in {

  imports = [
    ./pc24/zfs.nix
    ./pc24/nfs.nix
    ./pc24/seaweedfs.nix
    ./pc24/plex-ipv6-updater.nix
    ./palworld.nix
    # ../../overlays/nixarr/qbittorrent.nix
    ../../overlays/nixarr/overseerr.nix
  ];

  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  environment.systemPackages = (with pkgs; [
      attic-client
      bat
      curl
      dnsutils
      eza
      fd
      fzf
      git-lfs
      httpie
      jq
      just
      lsof
      nmap
      ripgrep
      rsync
      strace
      tcpdump
      unzip
      pipxNoCheck
      python3
      yq-go
      zoxide
      zip
    ]) ++ 
    ( with pkgs-unstable; [
      claude-code
      direnv
      nh
    ]
  );

  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = true;
    secrets = {
      inadyn-parawell-cloud = {
        owner = "inadyn";
        group = "inadyn";
        mode = "0400";
        restartUnits = [ "inadyn.service" ];
      };
      airvpn-san-jose-imai-conf = {
        sopsFile = ../../../secrets/hosts/pilatus/pc24.yaml;
        owner = "root";
        group = "root";
        mode = "0400";
      };
      palworld-admin-password = {
        sopsFile = ../../../secrets/hosts/pilatus/pc24.yaml;
        owner = "root";
        group = "root";
        mode = "0400";
      };
      palworld-server-password = {
        sopsFile = ../../../secrets/hosts/pilatus/pc24.yaml;
        owner = "root";
        group = "root";
        mode = "0400";
      };
      browserless-api-key = {
        sopsFile = ../../../secrets/hosts/pilatus/pc24.yaml;
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "1337x-flaresolverr-bridge.service" ];
      };
      kernel-api-key = {
        sopsFile = ../../../secrets/hosts/pilatus/pc24.yaml;
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "1337x-flaresolverr-bridge.service" ];
      };
    };
  };

  boot.kernel.sysctl = {
    "net.ipv6.bindv6only" = "0";
  };

  security.polkit.enable = true;
  time.timeZone = timezone;

  services = {
    tailscale.enable = true;

    inadyn = {
      enable = true;
      settings = {
        allow-ipv6 = true;
        custom."namecheap" = {
          username = tld;
          include = config.sops.secrets.inadyn-parawell-cloud.path;
          ddns-server = "dynamicdns.park-your-domain.com";
          ddns-path = "/update?domain=%u&password=%p&host=%h&ip=%i";
          hostname = [ host ];
          ddns-response = "<ErrCount>0</ErrCount>";
        };
      };
    };

    nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedTlsSettings = true;
      recommendedProxySettings = true;

      virtualHosts.${fqdn} = {
        locations."/" = {
          root = "/var/www/html";  # Default root directory, update as needed
        };
        locations."/.well-known/acme-challenge/" = {
          root = "/var/www/acme-challenge";
        };
      };
    };

    plex = {
      enable = true;
      dataDir = "/APPS/plex/config/Library/Application Support";
      package = pkgs-unstable.plex;
      group = "media";
      openFirewall = true;
    };

    flaresolverr = {
      enable = true;
      # package = pkgs-unstable.flaresolverr;
      openFirewall = true;
    };
    tor = {
      enable = true;

      # this is the critical switch that prevents SOCKSPort 0
      client.enable = true;

      # configure the SOCKS listener
      client.socksListenAddress = {
        addr = "127.0.0.1";
        port = 9050;
        IsolateSOCKSAuth = true;
      };

      settings = {
        SocksPolicy = [
          "accept 127.0.0.1"
          "reject *"
        ];
      };
    };

  };

  systemd.tmpfiles.rules = [
    "d /BIGBOY/proxmox-backups 0750 34 34 -"
    "d /BIGBOY/pbs 0750 34 34 -"
    "d /BIGBOY/pbs/etc 0750 34 34 -"
    "d /BIGBOY/pbs/logs 0750 34 34 -"
    "d /BIGBOY/pbs/lib 0750 34 34 -"

    # Declaratively manage permissions and POSIX ACLs for the Plex media directories
    # 1. Ensure directories exist, are owned by media group, and are group-writable (775)
    "d /BIGBOY/Plex/Incomplete 0775 - media - -"
    "d /BIGBOY/Plex/TV 0775 - media - -"
    "d /BIGBOY/Plex/Movies 0775 - media - -"
    "d /BIGBOY/Plex/Anime 0775 - media - -"
    "d /BIGBOY/Plex/Music 0775 - media - -"
    "d /BIGBOY/JBOD/Plex 0775 - media - -"

    # 2. Recursively force mode and group ownership for existing contents
    "Z /BIGBOY/Plex/Incomplete 0775 - media - -"
    "Z /BIGBOY/Plex/TV 0775 - media - -"
    "Z /BIGBOY/Plex/Movies 0775 - media - -"
    "Z /BIGBOY/Plex/Anime 0775 - media - -"
    "Z /BIGBOY/Plex/Music 0775 - media - -"
    "Z /BIGBOY/JBOD/Plex 0775 - media - -"

    # 3. Apply POSIX ACLs recursively (A) and as defaults (d) so new files inherit media group rwx
    "A /BIGBOY/Plex/Incomplete - - - - d:g:media:rwx,g:media:rwx"
    "A /BIGBOY/Plex/TV - - - - d:g:media:rwx,g:media:rwx"
    "A /BIGBOY/Plex/Movies - - - - d:g:media:rwx,g:media:rwx"
    "A /BIGBOY/Plex/Anime - - - - d:g:media:rwx,g:media:rwx"
    "A /BIGBOY/Plex/Music - - - - d:g:media:rwx,g:media:rwx"
    "A /BIGBOY/JBOD/Plex - - - - d:g:media:rwx,g:media:rwx"
  ];

  virtualisation.oci-containers.containers.pbs = {
    image = "docker.io/ayufan/proxmox-backup-server:latest";
    autoStart = true;
    extraOptions = [
      "--tmpfs=/run:rw,mode=0755"
    ];
    ports = [
      "8007:8007/tcp"
    ];
    environment = {
      TZ = timezone;
    };
    volumes = [
      "/BIGBOY/proxmox-backups:/backups"
      "/BIGBOY/pbs/etc:/etc/proxmox-backup"
      "/BIGBOY/pbs/logs:/var/log/proxmox-backup"
      "/BIGBOY/pbs/lib:/var/lib/proxmox-backup"
    ];
  };

  

  nixarr = {
    enable = true;
    mediaUsers = [ "plex" "jellyfin" "erikp" ];
    mediaDir = "/BIGBOY/nixarr/media";
    vpn = {
      enable = true;
      wgConf = config.sops.secrets.airvpn-san-jose-imai-conf.path;
      openTcpPorts = [ 12931 ];
      openUdpPorts = [ 12931 ];
    };
    radarr = {
      enable = true;
      package = pkgs-unstable.radarr;
      stateDir = "/APPS/arr-apps/radarr";
      openFirewall = true;
    };
    sonarr = {
      enable = true;
      package = pkgs-unstable.sonarr;
      stateDir = "/APPS/arr-apps/sonarr";
      openFirewall = true;
    };
    lidarr = {
      enable = true;
      package = pkgs-unstable.lidarr;
      stateDir = "/APPS/arr-apps/lidarr";
      openFirewall = true;
    };
    prowlarr = {
      enable = true;
      package = pkgs-unstable.prowlarr;
      # stateDir = "/APPS/arr-apps/prowlarr";
      openFirewall = true;
    };
    qbittorrent = {
      enable = true;
      package = pkgs-unstable.qbittorrent-nox;
      stateDir = "/APPS/arr-apps/qbittorrent";
      openFirewall = true;
      vpn.enable = true;
      uiPort = 10095;
      peerPort = 12931;
    };
    
    overseerr = {
      enable = true;
      stateDir = "/APPS/arr-apps/overseerr";
      openFirewall = true;
    };
    jellyfin = {
      enable = false;
      package = pkgs-unstable.jellyfin;
      stateDir = "/APPS/jellyfin";
      openFirewall = true;
    };
  };

  systemd.services.qbittorrent.serviceConfig = {
    # qBittorrent can exit cleanly, leaving systemd with no failed unit to restart.
    Restart = lib.mkForce "always";
    # Keep torrent traffic from starving Plex/media workloads.
    Nice = 10;
    CPUWeight = 10;
    IOWeight = 10;
    UMask = lib.mkForce "0002";
  };

  systemd.services.sonarr.serviceConfig.UMask = lib.mkForce "0002";
  systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";
  systemd.services.lidarr.serviceConfig.UMask = lib.mkForce "0002";
  systemd.services.prowlarr.serviceConfig.UMask = lib.mkForce "0002";
  systemd.services.prowlarr.environment.DOTNET_SYSTEM_NET_HTTP_SOCKETSHTTPHANDLER_HTTP2SUPPORT = "0";

  # 1337x sometimes returns a slow Varnish 503 to Prowlarr's initial request.
  # Browserless Unblock has a residential-proxy option that succeeds where the
  # server's shared IP fails Cloudflare. FlareSolverr remains a no-cost fallback.
  systemd.services."1337x-flaresolverr-bridge" =
    let
      bridge = pkgs.writeText "1337x-flaresolverr-bridge.py" ''
        import json
        import os
        import sqlite3
        import threading
        import time
        import urllib.error
        import urllib.parse
        import urllib.request
        from http.server import BaseHTTPRequestHandler, HTTPServer, ThreadingHTTPServer

        BROWSERLESS_ENDPOINT = "https://production-sfo.browserless.io/unblock"
        FLARESOLVERR_URL = "http://127.0.0.1:8191/v1"
        KERNEL_ENDPOINT = "https://api.onkernel.com"
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

        def store_usage(provider, payload):
            with database() as connection:
                connection.execute(
                    "INSERT OR REPLACE INTO provider_usage(provider, fetched_at, payload) VALUES (?, ?, ?)",
                    (provider, time.time(), json.dumps(payload)),
                )

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
                store_usage("kernel_sessions", {
                    "session_count": len(sessions),
                    "uptime_ms": sum(session.get("usage", {}).get("uptime_ms", 0) for session in sessions),
                    "source": "Kernel browser sessions API (not an account credit balance)",
                })
            except (OSError, RuntimeError, ValueError, urllib.error.URLError) as error:
                store_usage("kernel_sessions_error", {"error": type(error).__name__})

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

        threading.Thread(
            target=ThreadingHTTPServer(("0.0.0.0", 1337), StatsHandler).serve_forever,
            daemon=True,
        ).start()
        HTTPServer(("127.0.0.1", 8192), Handler).serve_forever()
      '';
    in {
      description = "1337x Browserless, Kernel, and FlareSolverr bridge for Prowlarr";
      after = [ "flaresolverr.service" ];
      requires = [ "flaresolverr.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${bridge}";
        Restart = "always";
        RestartSec = 2;
        DynamicUser = true;
        StateDirectory = "1337x-bridge";
        LoadCredential = [
          "browserless-api-key:${config.sops.secrets.browserless-api-key.path}"
          "kernel-api-key:${config.sops.secrets.kernel-api-key.path}"
        ];
      };
    };

  networking = {
    hostName = "pilatus-nix";
    enableIPv6 = false;
    nameservers = [ "1.1.1.1" "8.8.4.4" "8.8.8.8" "9.9.9.9" ];
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 1337 8007 ];
    };
  };

  # Declaratively apply local routing rules for the Nixarr VPN namespace confinement
  systemd.services.local-routing-rules = {
    description = "Apply local routing rules for Nixarr VPN confinement";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "-${pkgs.iproute2}/bin/ip rule add to 10.16.0.0/24 lookup main priority 5200";
      ExecStop = "-${pkgs.iproute2}/bin/ip rule del to 10.16.0.0/24 lookup main priority 5200";
    };
  };

  # Grant Plex permission to use the Intel Arc GPU for hardware-accelerated transcoding
  users.users.plex = {
    extraGroups = [ "video" "render" ];
  };



  system.stateVersion = "24.05";
}
