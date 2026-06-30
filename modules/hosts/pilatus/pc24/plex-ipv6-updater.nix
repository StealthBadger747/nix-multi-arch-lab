{ config, pkgs, lib, ... }:
let
  updaterScript = pkgs.writers.writePython3Bin "plex-ipv6-updater" { } ''
    import xml.etree.ElementTree as ET
    import os
    import subprocess
    import re
    import urllib.request
    import urllib.parse
    import sys

    PREF_PATH = (
        "/APPS/plex/config/Library/Application Support/"
        "Plex Media Server/Preferences.xml"
    )
    IP_PATH = "${pkgs.iproute2}/bin/ip"


    def get_ipv6_prefix():
        try:
            out = subprocess.check_output([
                IP_PATH,
                "-6",
                "addr",
                "show",
                "dev",
                "eth0",
                "scope",
                "global",
            ]).decode()
            m = re.search(r'inet6 ([0-9a-fA-F:]+/64)', out)
            if m:
                ipv6_cidr = m.group(1)
                prefix = ipv6_cidr.split('/')[0]
                parts = prefix.split(':')
                # Zero out the host bits for the /64 prefix
                prefix_64 = ":".join(parts[:4]) + "::/64"
                return prefix_64
        except Exception as e:
            print(f"Error getting IPv6 prefix: {e}", file=sys.stderr)
        return None


    def main():
        if not os.path.exists(PREF_PATH):
            print(
                f"Plex Preferences.xml not found at {PREF_PATH}",
                file=sys.stderr
            )
            sys.exit(1)

        # 1. Parse Preferences.xml
        try:
            tree = ET.parse(PREF_PATH)
            root = tree.getroot()
            token = root.get('PlexOnlineToken')
            current_lan = root.get('LanNetworksBandwidth', "")
        except Exception as e:
            print(f"Error parsing XML: {e}", file=sys.stderr)
            sys.exit(1)

        if not token:
            print(
                "PlexOnlineToken not found in Preferences.xml",
                file=sys.stderr
            )
            sys.exit(1)

        # 2. Get current IPv6 prefix
        prefix_64 = get_ipv6_prefix()
        if not prefix_64:
            print(
                "Could not find a valid global IPv6 prefix on eth0",
                file=sys.stderr
            )
            sys.exit(0)

        # 3. Determine new LAN configuration
        expected_lan = f"10.16.0.0/24,{prefix_64}"

        # 4. Update if necessary
        if current_lan != expected_lan:
            print(
                f"LAN Networks out of sync. "
                f"Current: '{current_lan}', Expected: '{expected_lan}'"
            )
            params = urllib.parse.urlencode({
                'LanNetworksBandwidth': expected_lan,
                'X-Plex-Token': token
            })
            url = f"http://127.0.0.1:32400/:/prefs?{params}"

            try:
                req = urllib.request.Request(url, method='PUT')
                with urllib.request.urlopen(req) as resp:
                    if resp.status == 200:
                        print("Successfully updated Plex LAN Networks preference.")
                    else:
                        print(
                            f"Plex returned non-200 status: {resp.status}",
                            file=sys.stderr
                        )
            except Exception as e:
                print(f"Error making API request to Plex: {e}", file=sys.stderr)
                sys.exit(1)
        else:
            print("Plex LAN Networks configuration is already up-to-date.")


    if __name__ == "__main__":
        main()
  '';
in
{
  systemd.services.plex-ipv6-updater = {
    description = "Update Plex LAN Networks with current IPv6 prefix";
    after = [ "plex.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${updaterScript}/bin/plex-ipv6-updater";
      User = "root";
    };
  };

  systemd.timers.plex-ipv6-updater = {
    description = "Timer for Plex LAN Networks IPv6 prefix updater";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "30m";
    };
  };
}
