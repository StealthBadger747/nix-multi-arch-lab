#!/usr/bin/env python3
import json
import os
import smtplib
import sys
from email.message import EmailMessage
from pathlib import Path


def require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"missing required environment variable: {name}")
    return value


def parse_recipients(raw: str) -> list[str]:
    recipients = [item.strip() for item in raw.split(",") if item.strip()]
    if not recipients:
        raise RuntimeError("VULNIX_EMAIL_TO is empty")
    return recipients


def build_text(summary: dict) -> str:
    hosts = summary.get("hosts", [])
    total_hosts = len(hosts)
    ok_hosts = sum(1 for h in hosts if h.get("status") == "ok")
    error_hosts = total_hosts - ok_hosts
    total_findings = sum(int(h.get("total_findings", 0)) for h in hosts if h.get("status") == "ok")
    total_unique_cves = sum(int(h.get("unique_cves", 0)) for h in hosts if h.get("status") == "ok")

    lines = [
        "Vulnix vulnerability report",
        "",
        f"Generated at: {summary.get('generated_at', 'unknown')}",
        f"Repository: {summary.get('repository', 'unknown')}",
        f"Ref: {summary.get('ref', 'unknown')}",
        "",
        f"Hosts scanned: {ok_hosts}/{total_hosts}",
        f"Hosts with scan errors: {error_hosts}",
        f"Total findings: {total_findings}",
        f"Total unique CVEs (sum of per-host unique counts): {total_unique_cves}",
        "",
        "Per-host summary:",
    ]

    for host in hosts:
        if host.get("status") != "ok":
            lines.append(f"- {host.get('host')}: scan failed ({host.get('error', 'unknown error')})")
            continue
        lines.append(
            "- {host}: findings={findings}, cves={cves}, critical={critical}, high={high}, medium={medium}, low={low}".format(
                host=host.get("host"),
                findings=host.get("total_findings", 0),
                cves=host.get("unique_cves", 0),
                critical=host.get("critical", 0),
                high=host.get("high", 0),
                medium=host.get("medium", 0),
                low=host.get("low", 0),
            )
        )

    lines.append("")
    lines.append("See attached summary.md and summary.json for details.")
    return "\n".join(lines)


def send_email(summary_json_path: Path, summary_md_path: Path) -> None:
    smtp_host = require_env("VULNIX_SMTP_HOST")
    smtp_port = int(require_env("VULNIX_SMTP_PORT"))
    smtp_user = require_env("VULNIX_SMTP_USER")
    smtp_pass = require_env("VULNIX_SMTP_PASS")
    smtp_connection = require_env("VULNIX_SMTP_CONNECTION").upper()
    recipients = parse_recipients(require_env("VULNIX_EMAIL_TO"))

    with summary_json_path.open("r", encoding="utf-8") as fh:
        summary = json.load(fh)

    subject = f"[vulnix] {summary.get('repository', 'repo')} {summary.get('ref', 'ref')} {summary.get('timestamp', '')}"
    text_body = build_text(summary)

    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = smtp_user
    message["To"] = ", ".join(recipients)
    message.set_content(text_body)

    if summary_md_path.exists():
        message.add_attachment(
            summary_md_path.read_bytes(),
            maintype="text",
            subtype="markdown",
            filename=summary_md_path.name,
        )

    message.add_attachment(
        summary_json_path.read_bytes(),
        maintype="application",
        subtype="json",
        filename=summary_json_path.name,
    )

    if smtp_connection == "SSL/TLS":
        with smtplib.SMTP_SSL(smtp_host, smtp_port, timeout=30) as smtp:
            smtp.login(smtp_user, smtp_pass)
            smtp.send_message(message)
        return

    raise RuntimeError("unsupported VULNIX_SMTP_CONNECTION; expected SSL/TLS")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: vulnix-email-report.py <summary.json> <summary.md>", file=sys.stderr)
        return 2

    summary_json_path = Path(sys.argv[1])
    summary_md_path = Path(sys.argv[2])
    if not summary_json_path.exists():
        print(f"summary file not found: {summary_json_path}", file=sys.stderr)
        return 2

    send_email(summary_json_path, summary_md_path)
    print(f"sent vulnix report email using {summary_json_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

